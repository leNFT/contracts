// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.8.17;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {ERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {ERC4626Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC4626Upgradeable.sol";
import {MathUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/math/MathUpgradeable.sol";
import {IAddressesProvider} from "../interfaces/IAddressesProvider.sol";
import {INativeTokenVault} from "../interfaces/INativeTokenVault.sol";
import {INativeToken} from "../interfaces/INativeToken.sol";
import {ILoanCenter} from "../interfaces/ILoanCenter.sol";
import {INFTOracle} from "../interfaces/INFTOracle.sol";
import {ITokenOracle} from "../interfaces/ITokenOracle.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {SafeERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import {IERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import {ValidationLogic} from "../libraries/logic/ValidationLogic.sol";
import {ContextUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ContextUpgradeable.sol";
import {WithdrawalRequestLogic} from "../libraries/logic/WithdrawalRequestLogic.sol";
import {DataTypes} from "../libraries/types/DataTypes.sol";
import {ConfigTypes} from "../libraries/types/ConfigTypes.sol";
import {PercentageMath} from "../libraries/math/PercentageMath.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "hardhat/console.sol";

contract NativeTokenVault is
    Initializable,
    ContextUpgradeable,
    ERC20Upgradeable,
    ERC4626Upgradeable,
    INativeTokenVault,
    OwnableUpgradeable,
    ReentrancyGuardUpgradeable
{
    IAddressesProvider private _addressProvider;
    uint256 internal _deployTimestamp;
    uint256 internal _lastRewardsTimestamp;
    ConfigTypes.LiquidationRewardConfig internal _liquidatonRewardsConfig;
    ConfigTypes.BoostConfig internal _boostConfig;
    ConfigTypes.StakingRewardConfig internal _stakingRewardsConfig;
    ConfigTypes.NativeTokenWithdrawalConfig
        internal _nativeTokenWithdrawalConfig;

    // User + collection to votes
    mapping(address => mapping(address => uint256)) private _votes;
    // User to used votes
    mapping(address => uint256) private _usedVotes;
    //Collections to votes
    mapping(address => uint256) private _collectionVotes;
    //User to withdraw requests
    mapping(address => DataTypes.WithdrawalRequest) private _withdrawalRequests;
    //Reserves that have their liquidations incentivized
    mapping(address => bool) private _reserveIncentives;

    using SafeERC20Upgradeable for IERC20Upgradeable;
    using WithdrawalRequestLogic for DataTypes.WithdrawalRequest;

    modifier onlyMarket() {
        require(
            _msgSender() == _addressProvider.getMarket(),
            "Caller must be Market contract"
        );
        _;
    }

    function initialize(
        IAddressesProvider addressProvider,
        string calldata name,
        string calldata symbol,
        IERC20Upgradeable asset,
        ConfigTypes.LiquidationRewardConfig calldata liquidatonRewardsConfig,
        ConfigTypes.BoostConfig calldata boostConfig,
        ConfigTypes.StakingRewardConfig calldata stakingRewardsConfig,
        ConfigTypes.NativeTokenWithdrawalConfig
            calldata nativeTokenWithdrawalConfig
    ) external initializer {
        __Ownable_init();
        __ERC20_init(name, symbol);
        __ERC4626_init(asset);
        _addressProvider = addressProvider;
        _liquidatonRewardsConfig = liquidatonRewardsConfig;
        _boostConfig = boostConfig;
        _stakingRewardsConfig = stakingRewardsConfig;
        _nativeTokenWithdrawalConfig = nativeTokenWithdrawalConfig;
        _deployTimestamp = block.timestamp;
    }

    function decimals()
        public
        view
        override(ERC20Upgradeable, ERC4626Upgradeable)
        returns (uint8)
    {
        return ERC4626Upgradeable.decimals();
    }

    function createWithdrawalRequest() external {
        ValidationLogic.validateCreateWithdrawalRequest(_addressProvider);
        // Create request and add it to the list
        _withdrawalRequests[_msgSender()].init(maxRedeem(_msgSender()));
    }

    function getWithdrawalRequest(address user)
        external
        view
        override
        returns (DataTypes.WithdrawalRequest memory)
    {
        return _withdrawalRequests[user];
    }

    function _withdraw(
        address caller,
        address receiver,
        address owner,
        uint256 assets,
        uint256 shares
    ) internal override {
        ValidationLogic.validateNativeTokenWithdraw(_addressProvider, shares);

        // Delete withdrawal request
        delete _withdrawalRequests[caller];

        ERC4626Upgradeable._withdraw(caller, receiver, owner, assets, shares);
    }

    function getWithdrawalCoolingPeriod()
        external
        view
        override
        returns (uint256)
    {
        return _nativeTokenWithdrawalConfig.coolingPeriod;
    }

    function setWithdrawalCoolingPeriod(uint256 coolingPeriod)
        external
        onlyOwner
    {
        _nativeTokenWithdrawalConfig.coolingPeriod = coolingPeriod;
    }

    function getWithdrawalActivePeriod()
        external
        view
        override
        returns (uint256)
    {
        return _nativeTokenWithdrawalConfig.activePeriod;
    }

    function setWithdrawalActivePeriod(uint256 activePeriod)
        external
        onlyOwner
    {
        _nativeTokenWithdrawalConfig.activePeriod = activePeriod;
    }

    function vote(uint256 votes, address collection)
        external
        override
        nonReentrant
    {
        ValidationLogic.validateVote(_addressProvider, votes);

        // Vote for a collection with the tokens we just minted
        _votes[_msgSender()][collection] += votes;
        _collectionVotes[collection] += votes;

        _usedVotes[_msgSender()] += votes;

        emit Vote(_msgSender(), collection, votes);
    }

    function removeVote(uint256 votes, address collection)
        external
        override
        nonReentrant
    {
        ValidationLogic.validateRemoveVote(_addressProvider, votes, collection);

        // Vote for a collection with the tokens we just minted
        _votes[_msgSender()][collection] -= votes;
        _collectionVotes[collection] -= votes;

        _usedVotes[_msgSender()] -= votes;

        emit RemoveVote(_msgSender(), collection, votes);
    }

    function getUserFreeVotes(address user)
        external
        view
        override
        returns (uint256)
    {
        return maxRedeem(user) - _usedVotes[user];
    }

    function getUserCollectionVotes(address user, address collection)
        external
        view
        override
        returns (uint256)
    {
        return _votes[user][collection];
    }

    function getLiquidationRewardFactor() external view returns (uint256) {
        return _liquidatonRewardsConfig.factor;
    }

    function setLiquidationRewardFactor(uint256 liquidationRewardFactor)
        external
        onlyOwner
    {
        _liquidatonRewardsConfig.factor = liquidationRewardFactor;
    }

    function getMaxLiquidationReward() external view returns (uint256) {
        return _liquidatonRewardsConfig.maxReward;
    }

    function setMaxLiquidationReward(uint256 maxLiquidationReward)
        external
        onlyOwner
    {
        _liquidatonRewardsConfig.maxReward = maxLiquidationReward;
    }

    function getLiquidationRewardPriceThreshold()
        external
        view
        returns (uint256)
    {
        return _liquidatonRewardsConfig.priceThreshold;
    }

    function setLiquidationRewardPriceThreshold(
        uint256 liquidationRewardPriceThreshold
    ) external onlyOwner {
        _liquidatonRewardsConfig
            .priceThreshold = liquidationRewardPriceThreshold;
    }

    function getLiquidationRewardPriceLimit() external view returns (uint256) {
        return _liquidatonRewardsConfig.priceLimit;
    }

    function setLiquidationRewardPriceLimit(uint256 liquidationRewardPriceLimit)
        external
        onlyOwner
    {
        _liquidatonRewardsConfig.priceLimit = liquidationRewardPriceLimit;
    }

    function getBoostFactor() external view returns (uint256) {
        return _boostConfig.factor;
    }

    function setBoostFactor(uint256 boostFactor) external onlyOwner {
        _boostConfig.factor = boostFactor;
    }

    function getBoostLimit() external view returns (uint256) {
        return _boostConfig.limit;
    }

    function setBoostLimit(uint256 boostLimit) external onlyOwner {
        _boostConfig.limit = boostLimit;
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
    ) external view override returns (uint256) {
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
            _liquidatonRewardsConfig.priceLimit
        );

        // Find the threshold from which rewards are given
        uint256 rewardsPriceThreshold = PercentageMath.percentMul(
            assetPrice,
            _liquidatonRewardsConfig.priceThreshold
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
                    _liquidatonRewardsConfig.factor);

            // Set the maximum amount for a liquidation reward
            if (reward > _liquidatonRewardsConfig.maxReward) {
                reward = _liquidatonRewardsConfig.maxReward;
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
        override
        onlyMarket
    {
        IERC20Upgradeable(_addressProvider.getNativeToken()).safeTransfer(
            liquidator,
            amount
        );
    }

    function _calculateLTVBoost(
        address user,
        address collection,
        uint256 votes
    ) internal view returns (uint256) {
        uint256 boost = 0;

        uint256 userCollectionActiveLoansCount = ILoanCenter(
            _addressProvider.getLoanCenter()
        ).getActiveLoansCount(user, collection) + 1;

        uint256 nativeTokenETHPrice = ITokenOracle(
            _addressProvider.getTokenOracle()
        ).getTokenETHPrice(_addressProvider.getNativeToken());

        uint256 pricePrecision = ITokenOracle(_addressProvider.getTokenOracle())
            .getPricePrecision();

        uint256 votesValue = (_convertToAssets(
            votes,
            MathUpgradeable.Rounding.Up
        ) * nativeTokenETHPrice) / pricePrecision;

        boost =
            (PercentageMath.PERCENTAGE_FACTOR * votesValue) /
            (userCollectionActiveLoansCount * _boostConfig.factor);

        // Max Boost Cap
        if (boost > _boostConfig.limit) {
            boost = _boostConfig.limit;
        }

        return boost;
    }

    function calculateLTVBoost(
        address user,
        address collection,
        uint256 votes
    ) external view returns (uint256) {
        return _calculateLTVBoost(user, collection, votes);
    }

    function getLTVBoost(address user, address collection)
        external
        view
        override
        returns (uint256)
    {
        return
            _calculateLTVBoost(user, collection, _collectionVotes[collection]);
    }

    function getStakingRewardsFactor() external view returns (uint256) {
        return _stakingRewardsConfig.factor;
    }

    function setStakingRewardsFactor(uint256 rewardsFactor) external onlyOwner {
        _stakingRewardsConfig.factor = rewardsFactor;
    }

    function getStakingMaxPeriods() external view returns (uint256) {
        return _stakingRewardsConfig.maxPeriods;
    }

    function setStakingMaxPeriods(uint256 maxPeriods) external onlyOwner {
        _stakingRewardsConfig.maxPeriods = maxPeriods;
    }

    function getStakingRewardsPeriod() external view returns (uint256) {
        return _stakingRewardsConfig.period;
    }

    function setStakingRewardsPeriod(uint256 rewardsPeriod) external onlyOwner {
        _stakingRewardsConfig.period = rewardsPeriod;
    }

    function getStakingRewards() public view returns (uint256) {
        uint256 rewards = 0;

        if (
            _stakingRewardsConfig.maxPeriods * _stakingRewardsConfig.period >
            block.timestamp - _deployTimestamp
        ) {
            rewards =
                (_stakingRewardsConfig.factor *
                    (_stakingRewardsConfig.maxPeriods *
                        _stakingRewardsConfig.period +
                        _deployTimestamp -
                        block.timestamp)) /
                (_stakingRewardsConfig.maxPeriods *
                    _stakingRewardsConfig.period);
        }

        return rewards;
    }

    function distributeStakingRewards() external nonReentrant {
        //The rewards can only be distributed if the rewards period has passed
        require(
            _lastRewardsTimestamp + _stakingRewardsConfig.period <
                block.timestamp,
            "Not enough time since last rewards distribution."
        );

        // Only give rewards until there are remaining periods
        require(
            _stakingRewardsConfig.maxPeriods * _stakingRewardsConfig.period >
                block.timestamp - _deployTimestamp,
            "Rewards period is over"
        );

        uint256 amount = getStakingRewards();
        INativeToken(_addressProvider.getNativeToken()).mintStakingRewardTokens(
                amount
            );

        // Update last rewards variable
        _lastRewardsTimestamp = block.timestamp;

        emit DistributeRewards(amount);
    }

    // Override transfer functions so the token is not transferable
    function transfer(address, uint256)
        public
        pure
        override(ERC20Upgradeable, IERC20Upgradeable)
        returns (bool)
    {
        revert("Transfer disabled");
    }

    function transferFrom(
        address,
        address,
        uint256
    ) public pure override(ERC20Upgradeable, IERC20Upgradeable) returns (bool) {
        revert("Transfer disabled");
    }
}
