// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.8.15;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {ERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {IMarketAddressesProvider} from "../interfaces/IMarketAddressesProvider.sol";
import {INativeTokenVault} from "../interfaces/INativeTokenVault.sol";
import {ILoanCenter} from "../interfaces/ILoanCenter.sol";
import {INFTOracle} from "../interfaces/INFTOracle.sol";
import {ITokenOracle} from "../interfaces/ITokenOracle.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {SafeERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import {IERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import {ValidationLogic} from "../libraries/logic/ValidationLogic.sol";
import {WithdrawRequestLogic} from "../libraries/logic/WithdrawRequestLogic.sol";
import {DataTypes} from "../libraries/types/DataTypes.sol";
import {PercentageMath} from "../libraries/math/PercentageMath.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract NativeTokenVault is
    Initializable,
    ERC20Upgradeable,
    INativeTokenVault,
    OwnableUpgradeable,
    ReentrancyGuard
{
    uint256 internal constant BOOST_RATIO = 30;
    uint256 internal constant MAX_BOOST = 2000; // 20%
    IMarketAddressesProvider private _addressProvider;
    address internal _nativeToken;
    // User + collection to votes
    mapping(address => mapping(address => uint256)) private _votes;
    // User to votes
    mapping(address => uint256) private _freeVotes;
    //Collections to votes
    mapping(address => uint256) private _collectionVotes;
    //User to withdraw requests
    mapping(address => DataTypes.WithdrawRequest) private _withdrawRequests;

    using SafeERC20Upgradeable for IERC20Upgradeable;
    using WithdrawRequestLogic for DataTypes.WithdrawRequest;

    modifier onlyMarket() {
        require(
            _msgSender() == address(_addressProvider.getMarketAddress()),
            "Caller must be Market contract"
        );
        _;
    }

    function initialize(
        IMarketAddressesProvider addressProvider,
        address nativeToken,
        string calldata name,
        string calldata symbol
    ) external initializer {
        __Ownable_init();
        __ERC20_init(name, symbol);
        _addressProvider = addressProvider;
        _nativeToken = nativeToken;
    }

    function deposit(uint256 amount) external override nonReentrant {
        ValidationLogic.validateNativeTokenDeposit(_nativeToken, amount);

        // Find how many tokens the reserve should mint
        uint256 veTokenAmount;
        if (totalSupply() == 0) {
            veTokenAmount = amount;
        } else {
            veTokenAmount = (amount * totalSupply()) / _getLockedBalance();
        }

        // Send native token from depositor to the vault
        IERC20Upgradeable(_nativeToken).safeTransferFrom(
            msg.sender,
            address(this),
            amount
        );

        //Mint veToken (locked) tokens
        _mint(msg.sender, veTokenAmount);

        //Update the number of unused votes
        _freeVotes[msg.sender] += veTokenAmount;

        emit Deposit(msg.sender, amount);
    }

    function createWithdrawRequest(uint256 amount)
        external
        override
        nonReentrant
    {
        ValidationLogic.validateCreateWithdrawRequest(_addressProvider, amount);
        //Create request and add it to the list
        _withdrawRequests[msg.sender].init(amount);
    }

    function getWithdrawRequest(address user)
        external
        view
        override
        returns (DataTypes.WithdrawRequest memory)
    {
        return _withdrawRequests[user];
    }

    function withdraw(uint256 amount) external override nonReentrant {
        ValidationLogic.validateNativeTokenWithdraw(_addressProvider, amount);

        // Find how many tokens the reserve should mint
        uint256 veTokenAmount;
        if (totalSupply() == 0) {
            veTokenAmount = amount;
        } else {
            veTokenAmount = (amount * totalSupply()) / _getLockedBalance();
        }

        // Burn the veToken
        _burn(msg.sender, amount);

        //Update the number of unused votes
        _freeVotes[msg.sender] -= veTokenAmount;

        // Withdraw the native token from the vault
        IERC20Upgradeable(_nativeToken).safeTransfer(msg.sender, amount);

        emit Withdraw(msg.sender, amount);
    }

    function vote(uint256 amount, address collection)
        external
        override
        nonReentrant
    {
        ValidationLogic.validateVote(_addressProvider, amount, collection);

        // Vote for a collection with the tokens we just minted
        _votes[msg.sender][collection] += amount;
        _collectionVotes[collection] += amount;

        _freeVotes[msg.sender] -= amount;

        emit Vote(msg.sender, collection, amount);
    }

    function removeVote(uint256 amount, address collection)
        external
        override
        nonReentrant
    {
        ValidationLogic.validateRemoveVote(
            _addressProvider,
            amount,
            collection
        );

        // Vote for a collection with the tokens we just minted
        _votes[msg.sender][collection] -= amount;
        _collectionVotes[collection] -= amount;

        _freeVotes[msg.sender] += amount;

        emit RemoveVote(msg.sender, collection, amount);
    }

    function getUserFreeVotes(address user) external view returns (uint256) {
        return _freeVotes[user];
    }

    function getUserCollectionVotes(address user, address collection)
        external
        view
        returns (uint256)
    {
        return _votes[user][collection];
    }

    function getCollateralizationBoost(address user, address collection)
        external
        view
        override
        returns (uint256)
    {
        uint256 boost = 0;

        uint256 userCollectionActiveLoansCount = ILoanCenter(
            _addressProvider.getLoanCenter()
        ).getUserCollectionActiveLoansCount(user, collection);

        uint256 collectionFloorPrice = INFTOracle(
            _addressProvider.getNFTOracle()
        ).getCollectionETHFloorPrice(collection);

        uint256 nativeTokenETHPrice = ITokenOracle(
            _addressProvider.getTokenOracle()
        ).getTokenETHPrice(_nativeToken);

        uint256 pricePrecision = ITokenOracle(_addressProvider.getTokenOracle())
            .getPricePrecision();

        uint256 votesValue = (_collectionVotes[collection] *
            nativeTokenETHPrice) / pricePrecision;

        uint256 activeLoansAssetValue = userCollectionActiveLoansCount *
            collectionFloorPrice;

        if (activeLoansAssetValue != 0) {
            boost =
                (PercentageMath.PERCENTAGE_FACTOR * votesValue) /
                (activeLoansAssetValue * BOOST_RATIO);

            // Max Boost Cap
            if (boost > MAX_BOOST) {
                boost = MAX_BOOST;
            }
        }

        return boost;
    }

    function getLockedBalance() external view override returns (uint256) {
        return _getLockedBalance();
    }

    function _getLockedBalance() internal view returns (uint256) {
        return IERC20Upgradeable(_nativeToken).balanceOf(address(this));
    }

    function getMaximumWithdrawalAmount(address user)
        external
        view
        returns (uint256)
    {
        uint256 veTokenFreeAmount = _freeVotes[user];
        uint256 maximumAmount;

        if (veTokenFreeAmount == 0) {
            maximumAmount = 0;
        } else {
            maximumAmount =
                (veTokenFreeAmount * _getLockedBalance()) /
                totalSupply();
        }

        return maximumAmount;
    }

    // Override transfer functions so the token is not transferable
    function transfer(address, uint256) public pure override returns (bool) {
        revert("Transfer disabled");
    }

    function transferFrom(
        address,
        address,
        uint256
    ) public pure override returns (bool) {
        revert("Transfer disabled");
    }
}
