// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.8.17;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {ERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
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
import {PercentageMath} from "../libraries/math/PercentageMath.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "hardhat/console.sol";

contract NativeTokenVault is
    Initializable,
    ContextUpgradeable,
    ERC20Upgradeable,
    INativeTokenVault,
    OwnableUpgradeable,
    ReentrancyGuardUpgradeable
{
    IAddressesProvider private _addressProvider;
    uint256 internal _deployTimestamp;
    DataTypes.LiquidationRewardParams internal _liquidatonRewardsParams;
    uint256 internal _lastRewardsTimestamp;
    DataTypes.BoostParams internal _boostParams;
    DataTypes.StakingRewardParams internal _stakingRewardsParams;

    // User + collection to votes
    mapping(address => mapping(address => uint256)) private _votes;
    // User to votes
    mapping(address => uint256) private _freeVotes;
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
            _msgSender() == address(_addressProvider.getMarketAddress()),
            "Caller must be Market contract"
        );
        _;
    }

    function initialize(
        IAddressesProvider addressProvider,
        string calldata name,
        string calldata symbol,
        DataTypes.LiquidationRewardParams calldata liquidatonRewardsParams,
        DataTypes.BoostParams calldata boostParams,
        DataTypes.StakingRewardParams calldata stakingRewardsParams
    ) external initializer {
        __Ownable_init();
        __ERC20_init(name, symbol);
        _addressProvider = addressProvider;
        _liquidatonRewardsParams = liquidatonRewardsParams;
        _boostParams = boostParams;
        _stakingRewardsParams = stakingRewardsParams;
        _deployTimestamp = block.timestamp;
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
            _msgSender(),
            address(this),
            amount
        );

        //Mint veToken (locked) tokens
        _mint(_msgSender(), veTokenAmount);

        //Update the number of unused votes
        _freeVotes[_msgSender()] += veTokenAmount;

        emit Deposit(_msgSender(), amount);
    }

    function createWithdrawalRequest(uint256 amount)
        external
        override
        nonReentrant
    {
        ValidationLogic.validateCreateWithdrawalRequest(
            _addressProvider,
            amount
        );
        //Create request and add it to the list
        _withdrawalRequests[_msgSender()].init(amount);
    }

    function getWithdrawalRequest(address user)
        external
        view
        override
        returns (DataTypes.WithdrawalRequest memory)
    {
        require(
            _withdrawalRequests[user].created == true,
            "User hasn't created any withdrawal requests"
        );
        return _withdrawalRequests[user];
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

        // Assert 1e-18 division errors
        assert(veTokenAmount > 0);

        // Burn the veTokens
        _burn(_msgSender(), amount);

        // Update the number of unused votes
        _freeVotes[_msgSender()] -= veTokenAmount;

        // Delete withdrawal request
        delete _withdrawalRequests[_msgSender()];

        // Withdraw the native token from the vault
        IERC20Upgradeable(_addressProvider.getNativeToken()).safeTransfer(
            _msgSender(),
            amount
        );

        emit Withdraw(_msgSender(), amount);
    }

    function vote(uint256 amount, address collection)
        external
        override
        nonReentrant
    {
        ValidationLogic.validateVote(_addressProvider, amount);

        // Vote for a collection with the tokens we just minted
        _votes[_msgSender()][collection] += amount;
        _collectionVotes[collection] += amount;

        _freeVotes[_msgSender()] -= amount;

        emit Vote(_msgSender(), collection, amount);
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
        _votes[_msgSender()][collection] -= amount;
        _collectionVotes[collection] -= amount;

        _freeVotes[_msgSender()] += amount;

        emit RemoveVote(_msgSender(), collection, amount);
    }

    function getUserFreeVotes(address user)
        external
        view
        override
        returns (uint256)
    {
        return _freeVotes[user];
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
        return _liquidatonRewardsParams.factor;
    }

    function setLiquidationRewardFactor(uint256 liquidationRewardFactor)
        external
        onlyOwner
    {
        _liquidatonRewardsParams.factor = liquidationRewardFactor;
    }

    function getMaxLiquidationReward() external view returns (uint256) {
        return _liquidatonRewardsParams.maxReward;
    }

    function setMaxLiquidationReward(uint256 maxLiquidationReward)
        external
        onlyOwner
    {
        _liquidatonRewardsParams.maxReward = maxLiquidationReward;
    }

    function getLiquidationRewardPriceThreshold()
        external
        view
        returns (uint256)
    {
        return _liquidatonRewardsParams.priceThreshold;
    }

    function setLiquidationRewardPriceThreshold(
        uint256 liquidationRewardPriceThreshold
    ) external onlyOwner {
        _liquidatonRewardsParams
            .priceThreshold = liquidationRewardPriceThreshold;
    }

    function getLiquidationRewardPriceLimit() external view returns (uint256) {
        return _liquidatonRewardsParams.priceLimit;
    }

    function setLiquidationRewardPriceLimit(uint256 liquidationRewardPriceLimit)
        external
        onlyOwner
    {
        _liquidatonRewardsParams.priceLimit = liquidationRewardPriceLimit;
    }

    function getBoostFactor() external view returns (uint256) {
        return _boostParams.factor;
    }

    function setBoostFactor(uint256 boostFactor) external onlyOwner {
        _boostParams.factor = boostFactor;
    }

    function getBoostLimit() external view returns (uint256) {
        return _boostParams.limit;
    }

    function setBoostLimit(uint256 boostLimit) external onlyOwner {
        _boostParams.limit = boostLimit;
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
            _liquidatonRewardsParams.priceLimit
        );

        // Find the threshold from which rewards are given
        uint256 rewardsPriceThreshold = PercentageMath.percentMul(
            assetPrice,
            _liquidatonRewardsParams.priceThreshold
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
                    _liquidatonRewardsParams.factor);

            // Set the maximum amount for a liquidation reward
            if (reward > _liquidatonRewardsParams.maxReward) {
                reward = _liquidatonRewardsParams.maxReward;
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

        if (totalSupply() == 0) {
            return 0;
        }

        uint256 votesToUnderlying = (votes * _getLockedBalance()) /
            totalSupply();
        uint256 votesValue = (votesToUnderlying * nativeTokenETHPrice) /
            pricePrecision;

        boost =
            (PercentageMath.PERCENTAGE_FACTOR * votesValue) /
            (userCollectionActiveLoansCount * _boostParams.factor);

        // Max Boost Cap
        if (boost > _boostParams.limit) {
            boost = _boostParams.limit;
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
        override
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

    function getStakingRewardsFactor() external view returns (uint256) {
        return _stakingRewardsParams.factor;
    }

    function setStakingRewardsFactor(uint256 rewardsFactor) external onlyOwner {
        _stakingRewardsParams.factor = rewardsFactor;
    }

    function getStakingMaxPeriods() external view returns (uint256) {
        return _stakingRewardsParams.maxPeriods;
    }

    function setStakingMaxPeriods(uint256 maxPeriods) external onlyOwner {
        _stakingRewardsParams.maxPeriods = maxPeriods;
    }

    function getStakingRewardsPeriod() external view returns (uint256) {
        return _stakingRewardsParams.period;
    }

    function setStakingRewardsPeriod(uint256 rewardsPeriod) external onlyOwner {
        _stakingRewardsParams.period = rewardsPeriod;
    }

    function getStakingRewards() public view returns (uint256) {
        uint256 rewards = 0;

        if (
            _stakingRewardsParams.maxPeriods * _stakingRewardsParams.period >
            block.timestamp - _deployTimestamp
        ) {
            rewards =
                (_stakingRewardsParams.factor *
                    (_stakingRewardsParams.maxPeriods *
                        _stakingRewardsParams.period +
                        _deployTimestamp -
                        block.timestamp)) /
                (_stakingRewardsParams.maxPeriods *
                    _stakingRewardsParams.period);
        }

        return rewards;
    }

    function distributeStakingRewards() external nonReentrant {
        //The rewards can only be distributed if the rewards period has passed
        require(
            _lastRewardsTimestamp + _stakingRewardsParams.period <
                block.timestamp,
            "Not enough time since last rewards distribution."
        );

        // Only give rewards until there are remaining periods
        require(
            _stakingRewardsParams.maxPeriods * _stakingRewardsParams.period >
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
