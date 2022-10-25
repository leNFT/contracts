// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.8.15;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {ERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {IAddressesProvider} from "../interfaces/IAddressesProvider.sol";
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
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "hardhat/console.sol";

contract NativeTokenVault is
    Initializable,
    ERC20Upgradeable,
    INativeTokenVault,
    OwnableUpgradeable,
    ReentrancyGuardUpgradeable
{
    IAddressesProvider private _addressProvider;
    uint256 internal _boostFactor;
    uint256 internal _boostLimit;
    uint256 internal _liquidationRewardFactor;
    uint256 internal _maxLiquidationReward;
    uint256 internal _liquidationRewardPriceThreshold;
    uint256 internal _liquidationRewardPriceLimit;
    // User + collection to votes
    mapping(address => mapping(address => uint256)) private _votes;
    // User to votes
    mapping(address => uint256) private _freeVotes;
    //Collections to votes
    mapping(address => uint256) private _collectionVotes;
    //User to withdraw requests
    mapping(address => DataTypes.WithdrawRequest) private _withdrawRequests;
    //Reserves that have their liquidations incentivized
    mapping(address => bool) private _reserveIncentives;

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
        IAddressesProvider addressProvider,
        string calldata name,
        string calldata symbol,
        uint256 maxLiquidationReward,
        uint256 liquidationRewardFactor,
        uint256 liquidationRewardPriceThreshold,
        uint256 liquidationRewardPriceLimit,
        uint256 boostLimit,
        uint256 boostFactor
    ) external initializer {
        __Ownable_init();
        __ERC20_init(name, symbol);
        _addressProvider = addressProvider;
        _maxLiquidationReward = maxLiquidationReward;
        _liquidationRewardFactor = liquidationRewardFactor;
        _liquidationRewardPriceThreshold = liquidationRewardPriceThreshold;
        _liquidationRewardPriceLimit = liquidationRewardPriceLimit;
        _boostLimit = boostLimit;
        _boostFactor = boostFactor;
    }

    function deposit(uint256 amount) external override nonReentrant {
        ValidationLogic.validateNativeTokenDeposit(
            _addressProvider.getNativeToken(),
            amount
        );

        // Find how many tokens the reserve should mint
        uint256 veTokenAmount;
        if (totalSupply() == 0) {
            veTokenAmount = amount;
        } else {
            veTokenAmount = (amount * totalSupply()) / _getLockedBalance();
        }

        // Send native token from depositor to the vault
        IERC20Upgradeable(_addressProvider.getNativeToken()).safeTransferFrom(
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
        require(
            _withdrawRequests[user].created == true,
            "User hasn't created any withdrawal requests"
        );
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

        assert(veTokenAmount > 0);

        // Burn the veToken
        _burn(msg.sender, amount);

        //Update the number of unused votes
        _freeVotes[msg.sender] -= veTokenAmount;

        // Withdraw the native token from the vault
        IERC20Upgradeable(_addressProvider.getNativeToken()).safeTransfer(
            msg.sender,
            amount
        );

        emit Withdraw(msg.sender, amount);
    }

    function vote(uint256 amount, address collection)
        external
        override
        nonReentrant
    {
        ValidationLogic.validateVote(_addressProvider, amount);

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

    function getLiquidationRewardFactor() external view returns (uint256) {
        return _liquidationRewardFactor;
    }

    function setLiquidationRewardFactor(uint256 liquidationRewardFactor)
        external
        onlyOwner
    {
        _liquidationRewardFactor = liquidationRewardFactor;
    }

    function getMaxLiquidationReward() external view returns (uint256) {
        return _maxLiquidationReward;
    }

    function setMaxLiquidationReward(uint256 maxLiquidationReward)
        external
        onlyOwner
    {
        _maxLiquidationReward = maxLiquidationReward;
    }

    function getLiquidationRewardPriceThreshold()
        external
        view
        returns (uint256)
    {
        return _liquidationRewardPriceLimit;
    }

    function setLiquidationRewardPriceThreshold(
        uint256 liquidationRewardPriceThreshold
    ) external onlyOwner {
        _liquidationRewardPriceThreshold = liquidationRewardPriceThreshold;
    }

    function getLiquidationRewardPriceLimit() external view returns (uint256) {
        return _liquidationRewardPriceLimit;
    }

    function setLiquidationRewardPriceLimit(uint256 liquidationRewardPriceLimit)
        external
        onlyOwner
    {
        _liquidationRewardPriceLimit = liquidationRewardPriceLimit;
    }

    function getBoostFactor() external view returns (uint256) {
        return _boostFactor;
    }

    function setBoostFactor(uint256 boostFactor) external onlyOwner {
        _boostFactor = boostFactor;
    }

    function getBoostLimit() external view returns (uint256) {
        return _boostLimit;
    }

    function setBoostLimit(uint256 boostLimit) external onlyOwner {
        _boostLimit = boostLimit;
    }

    function isReserveIncentivized(address reserve)
        external
        view
        returns (bool)
    {
        return _reserveIncentives[reserve];
    }

    function setReserveIncentives(address reserve, bool mode)
        external
        onlyOwner
    {
        _reserveIncentives[reserve] = mode;
    }

    function getLiquidationReward(
        address reserve,
        uint256 reserveTokenPrice,
        uint256 assetPrice,
        uint256 liquidationPrice
    ) external view returns (uint256) {
        uint256 reward = 0;

        // If the reserve is not in the list of incentived reserves it gets no reward
        if (_reserveIncentives[reserve] == false) {
            return reward;
        }

        ITokenOracle tokenOracle = ITokenOracle(
            _addressProvider.getTokenOracle()
        );

        // Find the limit until which rewards are given
        uint256 rewardsPriceLimit = PercentageMath.percentMul(
            assetPrice,
            _liquidationRewardPriceLimit
        );

        // Find the threshold from which rewards are given
        uint256 rewardsPriceThreshold = PercentageMath.percentMul(
            assetPrice,
            _liquidationRewardPriceThreshold
        );
        console.log("rewardsPriceLimit", rewardsPriceLimit);
        console.log("rewardsPriceThreshold", rewardsPriceThreshold);

        if (
            liquidationPrice < rewardsPriceLimit &&
            liquidationPrice > rewardsPriceThreshold
        ) {
            console.log(
                "(liquidationPrice - rewardsPriceThreshold)",
                (liquidationPrice - rewardsPriceThreshold)
            );
            reward =
                ((liquidationPrice - rewardsPriceThreshold) *
                    tokenOracle.getPricePrecision()**3) /
                (reserveTokenPrice *
                    tokenOracle.getTokenETHPrice(
                        _addressProvider.getNativeToken()
                    ) *
                    _liquidationRewardFactor);

            // Set the maximum amount for a liquidation reward
            if (reward > _maxLiquidationReward) {
                reward = _maxLiquidationReward;
            }

            // If the vault has not enough balance to cover the reward
            uint256 rewardVaultBalance = IERC20Upgradeable(
                _addressProvider.getNativeToken()
            ).balanceOf(address(this));
            if (reward > rewardVaultBalance) {
                reward = rewardVaultBalance;
            }
        }

        return reward;
    }

    function sendLiquidationReward(address liquidator, uint256 amount)
        external
        onlyMarket
    {
        IERC20Upgradeable(_addressProvider.getNativeToken()).safeTransfer(
            liquidator,
            amount
        );
    }

    function getVoteCollateralizationBoost(address user, address collection)
        external
        view
        override
        returns (uint256)
    {
        uint256 boost = 0;

        uint256 userCollectionActiveLoansCount = ILoanCenter(
            _addressProvider.getLoanCenter()
        ).getActiveLoansCount(user, collection) + 1;

        uint256 nativeTokenETHPrice = ITokenOracle(
            _addressProvider.getTokenOracle()
        ).getTokenETHPrice(_addressProvider.getNativeToken());

        uint256 pricePrecision = ITokenOracle(_addressProvider.getTokenOracle())
            .getPricePrecision();

        uint256 votesValue = (_collectionVotes[collection] *
            nativeTokenETHPrice) / pricePrecision;

        boost =
            (PercentageMath.PERCENTAGE_FACTOR * votesValue) /
            (userCollectionActiveLoansCount * _boostFactor);

        // Max Boost Cap
        if (boost > _boostLimit) {
            boost = _boostLimit;
        }

        return boost;
    }

    function getLockedBalance() external view override returns (uint256) {
        return _getLockedBalance();
    }

    function _getLockedBalance() internal view returns (uint256) {
        return
            IERC20Upgradeable(_addressProvider.getNativeToken()).balanceOf(
                address(this)
            );
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
