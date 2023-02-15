// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.8.17;

import {IAddressesProvider} from "../interfaces/IAddressesProvider.sol";
import {ILendingMarket} from "../interfaces/ILendingMarket.sol";
import {IWETH} from "../interfaces/IWETH.sol";
import {IGenesisNFT} from "../interfaces/IGenesisNFT.sol";
import {ICurvePool} from "../interfaces/ICurvePool.sol";
import {INativeToken} from "../interfaces/INativeToken.sol";
import {IVotingEscrow} from "../interfaces/IVotingEscrow.sol";
import {DataTypes} from "../libraries/types/DataTypes.sol";
import {IWETH} from "../interfaces/IWETH.sol";
import {SafeERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import {IERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import {IERC165Upgradeable} from "@openzeppelin/contracts-upgradeable/utils/introspection/IERC165Upgradeable.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {ERC721Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC721/ERC721Upgradeable.sol";
import {ERC721URIStorageUpgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC721/extensions/ERC721URIStorageUpgradeable.sol";
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
    ERC721URIStorageUpgradeable,
    OwnableUpgradeable,
    IGenesisNFT,
    ReentrancyGuardUpgradeable
{
    using CountersUpgradeable for CountersUpgradeable.Counter;
    using SafeERC20Upgradeable for IERC20Upgradeable;

    IAddressesProvider private _addressProvider;
    uint256 _cap;
    uint256 _price;
    uint256 _maxLocktime;
    uint256 _minLocktime;
    uint256 _nativeTokenFactor;
    address _tradingPool;
    address payable _devAddress;
    uint256 _ltvBoost;
    CountersUpgradeable.Counter private _tokenIdCounter;

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

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
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

    function getNativeTokenReward(
        uint256 amount,
        uint256 locktime
    ) public view returns (uint256) {
        return
            ((amount * locktime * (_cap - _tokenIdCounter.current())) /
                _nativeTokenFactor) * 1e18;
    }

    function setTradingPool(address pool) external onlyOwner {
        _tradingPool = pool;
    }

    function mintCount() external view returns (uint256) {
        return _tokenIdCounter.current() - 1;
    }

    function mint(
        uint256 locktime,
        string[] memory uris
    ) external payable nonReentrant {
        // Make sure locktimes are within limits
        require(locktime >= _minLocktime, "Locktime is lower than threshold");
        require(locktime <= _maxLocktime, "Locktime is higher than limit");

        // Make sure the genesis incentived pool is set
        require(_tradingPool != address(0), "Incentivized pool is not set.");

        // Make sure there are enough tokens to mint
        require(
            _tokenIdCounter.current() + uris.length <= getCap(),
            "Maximum cap exceeded"
        );

        // Make sure the user sent enough ETH
        uint256 buyPrice = _price * uris.length;
        require(msg.value == buyPrice, "Tx value is not equal to price");

        // Get the amount of ETH to deposit to the pool
        uint256 ethAmount = (2 * buyPrice) / 3;

        // Get the amount of LE tokens to pair with the ETH
        uint256[2] memory balances = ICurvePool(_tradingPool).get_balances();
        uint256 tokenAmount;

        if (balances[0] == 0) {
            tokenAmount = ethAmount * 15000;
        } else {
            tokenAmount = (ethAmount * balances[1]) / balances[0];
        }

        // Mint LE tokens
        uint256 totalRewards = getNativeTokenReward(uris.length, locktime);
        INativeToken(_addressProvider.getNativeToken()).mintGenesisTokens(
            tokenAmount + totalRewards
        );

        // Approve the pool to spend LE tokens
        IERC20Upgradeable(_addressProvider.getNativeToken()).approve(
            _tradingPool,
            tokenAmount
        );

        // Deposit tokens to the pool and the LP amount
        uint256 lpAmount = ICurvePool(_tradingPool).add_liquidity{
            value: ethAmount
        }([ethAmount, tokenAmount], 0);

        // Approve the voting escrow to spend LE tokens so they can be locked
        IERC20Upgradeable(_addressProvider.getNativeToken()).approve(
            _addressProvider.getVotingEscrow(),
            totalRewards
        );

        IVotingEscrow(_addressProvider.getVotingEscrow()).createLock(
            _msgSender(),
            totalRewards,
            block.timestamp + locktime
        );

        // Send the rest of the ETH to the dev address
        (bool sent, ) = _devAddress.call{value: buyPrice - ethAmount}("");
        require(sent, "Failed to send Ether to dev fund");

        uint256 tokenId;
        for (uint256 i = 0; i < uris.length; i++) {
            tokenId = _tokenIdCounter.current();

            // Mint genesis NFT
            _safeMint(_msgSender(), tokenId);

            //Set URI
            _setTokenURI(tokenId, uris[i]);

            // Add mint details
            _mintDetails[tokenId] = DataTypes.MintDetails(
                block.timestamp,
                locktime,
                lpAmount / uris.length
            );

            //Increase supply
            _tokenIdCounter.increment();

            emit Mint(_msgSender(), tokenId);
        }
    }

    function getPrice() external view returns (uint256) {
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

    function burn(uint256[] memory tokenIds) external nonReentrant {
        uint256 lpAmountSum = 0;
        for (uint256 i = 0; i < tokenIds.length; i++) {
            //Require the caller owns the token
            require(
                _msgSender() == ERC721Upgradeable.ownerOf(tokenIds[i]),
                "Must own token"
            );
            // Token can only be burned after locktime is over
            require(
                block.timestamp >= getUnlockTimestamp(tokenIds[i]),
                "Token is still locked"
            );

            // Add the LP amount to the sum
            lpAmountSum = _mintDetails[tokenIds[i]].lpAmount;

            // Burn genesis NFT
            _burn(tokenIds[i]);
            emit Burn(tokenIds[i]);
        }

        // Withdraw LP tokens from the pool
        uint256 withdrawAmount = ICurvePool(_tradingPool)
            .remove_liquidity_one_coin(lpAmountSum, uint128(1), uint256(0));

        // Burn half of the received LE tokens
        INativeToken(_addressProvider.getNativeToken()).burnGenesisTokens(
            withdrawAmount / 2
        );

        // Send the rest of the LE tokens to the owner of the Genesis NFT
        IERC20Upgradeable(_addressProvider.getNativeToken()).transfer(
            _msgSender(),
            withdrawAmount / 2
        );
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
