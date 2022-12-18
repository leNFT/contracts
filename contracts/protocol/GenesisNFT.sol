// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.8.17;

import {IAddressesProvider} from "../interfaces/IAddressesProvider.sol";
import {ILendingMarket} from "../interfaces/ILendingMarket.sol";
import {IWETH} from "../interfaces/IWETH.sol";
import {IGenesisNFT} from "../interfaces/IGenesisNFT.sol";
import {INativeToken} from "../interfaces/INativeToken.sol";
import {DataTypes} from "../libraries/types/DataTypes.sol";
import {IWETH} from "../interfaces/IWETH.sol";
import {IERC165Upgradeable} from "@openzeppelin/contracts-upgradeable/utils/introspection/IERC165Upgradeable.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {ERC721Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC721/ERC721Upgradeable.sol";
import {ERC721URIStorageUpgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC721/extensions/ERC721URIStorageUpgradeable.sol";
import {ERC721BurnableUpgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC721/extensions/ERC721BurnableUpgradeable.sol";
import {CountersUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/CountersUpgradeable.sol";
import {ERC721EnumerableUpgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC721/extensions/ERC721EnumerableUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {ContextUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ContextUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "hardhat/console.sol";

contract GenesisNFT is
    Initializable,
    ContextUpgradeable,
    ERC721Upgradeable,
    ERC721EnumerableUpgradeable,
    ERC721BurnableUpgradeable,
    ERC721URIStorageUpgradeable,
    OwnableUpgradeable,
    IGenesisNFT,
    ReentrancyGuardUpgradeable
{
    using CountersUpgradeable for CountersUpgradeable.Counter;

    IAddressesProvider private _addressProvider;
    uint256 _cap;
    uint256 _price;
    uint256 _maxLocktime;
    uint256 _minLocktime;
    uint256 _nativeTokenFactor;
    address payable _devAddress;
    uint256 _ltvBoost;
    CountersUpgradeable.Counter private _tokenIdCounter;
    address _mintReserve;

    // NFT token id to bool that's true if NFT is being used to charge a loan
    mapping(uint256 => bool) private _active;

    // NFT token id to information about its mint
    mapping(uint256 => DataTypes.MintDetails) private _mintDetails;

    modifier onlyMarket() {
        require(
            _msgSender() == _addressProvider.getLendingMarket(),
            "Caller must be Market contract"
        );
        _;
    }

    function initialize(
        IAddressesProvider addressProvider,
        string calldata name,
        string calldata symbol,
        uint256 cap,
        uint256 price,
        uint256 ltvBoost,
        uint256 nativeTokenFactor,
        uint256 maxLocktime,
        uint256 minLocktime,
        address payable devAddress
    ) external initializer {
        __ERC721Enumerable_init();
        __ERC721Burnable_init();
        __Ownable_init();
        __ERC721_init(name, symbol);
        _addressProvider = addressProvider;
        _cap = cap;
        _price = price;
        _ltvBoost = ltvBoost;
        _nativeTokenFactor = nativeTokenFactor;
        _maxLocktime = maxLocktime;
        _minLocktime = minLocktime;
        _devAddress = devAddress;

        // Start from token_id 1 to reserve 0
        _tokenIdCounter.increment();
    }

    function _baseURI() internal pure override returns (string memory) {
        return "ipfs://";
    }

    function tokenURI(
        uint256 tokenId
    )
        public
        view
        override(ERC721Upgradeable, ERC721URIStorageUpgradeable)
        returns (string memory)
    {
        return ERC721URIStorageUpgradeable.tokenURI(tokenId);
    }

    function getCap() public view returns (uint256) {
        return _cap;
    }

    function getLTVBoost() external view override returns (uint256) {
        return _ltvBoost;
    }

    function setLTVBoost(uint256 newLTVBoost) external onlyOwner {
        _ltvBoost = newLTVBoost;
    }

    function getActiveState(
        uint256 tokenId
    ) external view override returns (bool) {
        return _active[tokenId];
    }

    function setActiveState(
        uint256 tokenId,
        bool newState
    ) external override onlyMarket {
        _active[tokenId] = newState;
    }

    function getNativeTokensReward(
        uint256 locktime
    ) public view returns (uint256) {
        return
            ((locktime * (_cap - _tokenIdCounter.current())) /
                _nativeTokenFactor) * 10 ** 18;
    }

    function getMintReserve() external view returns (address) {
        return _mintReserve;
    }

    function setMintReserve(address mintReserve) external onlyOwner {
        _mintReserve = mintReserve;
    }

    function mintCount() external view returns (uint256) {
        return _tokenIdCounter.current() - 1;
    }

    function mint(
        uint256 locktime,
        string memory uri
    ) external payable nonReentrant returns (uint256) {
        // Make sure the genesis reserve is set
        require(
            _mintReserve != address(0),
            "Genesis mint deposit reserve is not set."
        );

        // Make sure there's still enough tkens to mint
        uint256 tokenId = _tokenIdCounter.current();
        require(tokenId <= getCap(), "All NFTs have been minted");

        // Make sure locktime is within limits
        require(locktime >= _minLocktime, "Locktime is lower than threshold");
        require(locktime <= _maxLocktime, "Locktime is higher than limit");

        // Set a buying price
        require(msg.value == _price, "Tx value is not equal to price");

        //Wrap and Deposit 2/3 into the reserve
        uint256 depositAmount = (2 * _price) / 3;
        address weth = _addressProvider.getWETH();
        IWETH(weth).deposit{value: depositAmount}();
        IWETH(weth).approve(_mintReserve, depositAmount);
        IERC4626(_mintReserve).deposit(depositAmount, (address(this)));

        // Send the rest to the dev address
        (bool sent, ) = _devAddress.call{value: _price - depositAmount}("");
        require(sent, "Failed to send Ether to dev fund");

        // Send leNFT tokens to the caller
        INativeToken(_addressProvider.getNativeToken()).mintGenesisTokens(
            _msgSender(),
            getNativeTokensReward(locktime)
        );

        //Mint genesis NFT
        _safeMint(_msgSender(), tokenId);

        //Set URI
        _setTokenURI(tokenId, uri);

        // Add mint details
        _mintDetails[tokenId] = DataTypes.MintDetails(
            block.timestamp,
            locktime
        );

        //Increase supply
        _tokenIdCounter.increment();

        emit Mint(_msgSender(), tokenId);

        return tokenId;
    }

    function getETHPrice() external view returns (uint256) {
        return _price;
    }

    function getUnlockTimestamp(uint256 tokenId) public view returns (uint256) {
        return _mintDetails[tokenId].timestamp + _mintDetails[tokenId].locktime;
    }

    function _burn(
        uint256 tokenId
    ) internal override(ERC721Upgradeable, ERC721URIStorageUpgradeable) {
        ERC721URIStorageUpgradeable._burn(tokenId);
    }

    function burn(uint256 tokenId) public override nonReentrant {
        //Require the caller owns the token
        require(
            _msgSender() == ERC721Upgradeable.ownerOf(tokenId),
            "Must own token"
        );
        // Token can only be burned after locktime is over
        require(
            block.timestamp >= getUnlockTimestamp(tokenId),
            "Token is still locked"
        );

        // Withdraw ETH deposited in the reserve
        uint256 withdrawAmount = (2 * _price) / 3;
        address weth = _addressProvider.getWETH();
        IERC4626(_mintReserve).withdraw(
            withdrawAmount,
            address(this),
            address(this)
        );
        IWETH(weth).withdraw(withdrawAmount);
        (bool sent, ) = _msgSender().call{value: withdrawAmount}("");
        require(sent, "Failed to send Ether");

        // Burn genesis NFT
        _burn(tokenId);
        emit Burn(tokenId);
    }

    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 tokenId,
        uint256 batchSize
    ) internal override(ERC721Upgradeable, ERC721EnumerableUpgradeable) {
        require(
            _active[tokenId] == false,
            "Cannot transfer token - currently locked in an active loan"
        );
        ERC721EnumerableUpgradeable._beforeTokenTransfer(
            from,
            to,
            tokenId,
            batchSize
        );
    }

    function supportsInterface(
        bytes4 interfaceId
    )
        public
        view
        override(
            IERC165Upgradeable,
            ERC721Upgradeable,
            ERC721EnumerableUpgradeable
        )
        returns (bool)
    {
        return ERC721EnumerableUpgradeable.supportsInterface(interfaceId);
    }

    // Function to receive Ether. msg.data must be empty
    receive() external payable {}
}
