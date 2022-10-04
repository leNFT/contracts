// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.8.15;

import {IAddressesProvider} from "../interfaces/IAddressesProvider.sol";
import {IMarket} from "../interfaces/IMarket.sol";
import {IGenesisNFT} from "../interfaces/IGenesisNFT.sol";
import {INativeToken} from "../interfaces/INativeToken.sol";
import {DataTypes} from "../libraries/types/DataTypes.sol";
import {IWETH} from "../interfaces/IWETH.sol";
import {ERC721Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC721/ERC721Upgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";

contract GenesisNFT is
    Initializable,
    ERC721Upgradeable,
    IGenesisNFT,
    OwnableUpgradeable,
    ReentrancyGuardUpgradeable
{
    IAddressesProvider private _addressProvider;
    uint256 _cap;
    uint256 _supply;
    uint256 _price;
    uint256 _maxLocktime;
    uint256 _nativeTokenFactor;
    address _weth;
    address payable _devAddress;
    uint256 _ltvBoost;

    // NFT token id to bool that's true if NFT is being used to charge a loan
    mapping(uint256 => bool) private _active;

    // NFT token id to information about its mint
    mapping(uint256 => DataTypes.MintDetails) private _mintDetails;

    modifier onlyMarket() {
        require(
            _msgSender() == address(_addressProvider.getMarketAddress()),
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
        address weth,
        uint256 ltvBoost,
        uint256 nativeTokenFactor,
        uint256 maxLocktime,
        address payable devAddress
    ) external initializer {
        __Ownable_init();
        __ERC721_init(name, symbol);
        _addressProvider = addressProvider;
        _cap = cap;
        _price = price;
        _weth = weth;
        _ltvBoost = ltvBoost;
        _nativeTokenFactor = nativeTokenFactor;
        _maxLocktime = maxLocktime;
        _devAddress = devAddress;
    }

    function getCap() public view returns (uint256) {
        return _cap;
    }

    function getSupply() external view returns (uint256) {
        return _supply;
    }

    function getLTVBoost() external view returns (uint256) {
        return _ltvBoost;
    }

    function setLTVBoost(uint256 newLTVBoost) external onlyOwner {
        _ltvBoost = newLTVBoost;
    }

    function getActiveState(uint256 tokenId) external view returns (bool) {
        return _active[tokenId];
    }

    function setActiveState(uint256 tokenId, bool newState)
        external
        onlyMarket
    {
        _active[tokenId] = newState;
    }

    function setNativeTokenFactor(uint256 newFactor) external onlyOwner {
        _nativeTokenFactor = newFactor;
    }

    function mint(uint256 locktime)
        external
        payable
        nonReentrant
        returns (uint256)
    {
        // Make sure there's still enough tkens to mint
        require(_supply + 1 <= getCap(), "All NFTs have been minted");

        // Make sure locktime is within limits
        require(locktime < _maxLocktime, "Locktime is higher than limit");

        // Set a buying price
        require(msg.value == _price);

        //Wrap and Deposit 2/3 into the reserve
        IWETH WETH = IWETH(_weth);
        uint256 depositAmount = (2 * _price) / 3;
        WETH.deposit{value: depositAmount}();
        IMarket(_addressProvider.getMarketAddress()).deposit(
            _weth,
            depositAmount
        );

        // Send the rest to the dev fund
        (bool sent, ) = _devAddress.call{value: _price - depositAmount}("");
        require(sent, "Failed to send Ether to dev fund");

        // Send leNFT tokens to the caller
        uint256 nativeTokenAmount = (locktime * (_cap - _supply)) /
            _nativeTokenFactor;
        INativeToken(_addressProvider.getNativeToken()).mintGenesisTokens(
            msg.sender,
            nativeTokenAmount
        );

        //Increase supply
        _supply += 1;

        //Mint token
        _safeMint(msg.sender, _supply);

        // Add mint details
        _mintDetails[_supply] = DataTypes.MintDetails(
            block.timestamp,
            locktime
        );

        emit Mint(msg.sender, _supply);

        return _supply;
    }

    function burn(uint256 tokenId) external nonReentrant {
        // Require caller owns the NFT being burned
        require(
            msg.sender == ERC721Upgradeable.ownerOf(tokenId),
            "Must own token"
        );

        // Withdraw ETH deposited in the reserve
        IWETH WETH = IWETH(_weth);
        uint256 withdrawAmount = (2 * _price) / 3;
        IMarket(_addressProvider.getMarketAddress()).withdraw(
            _weth,
            withdrawAmount
        );
        WETH.withdraw(withdrawAmount);

        // Send ETH back to NFT owner
        (bool sent, ) = msg.sender.call{value: withdrawAmount}("");
        require(sent, "Failed to send Ether");

        // Burn NFT token
        _burn(tokenId);

        emit Burn(tokenId);
    }

    function _beforeTokenTransfer(
        address,
        address,
        uint256 tokenId
    ) internal view override {
        require(
            _active[tokenId] == false,
            "Cannot transfer token - currently locked in an active loan"
        );
    }
}
