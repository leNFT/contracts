// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.8.17;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {ILiquidationRewards} from "../interfaces/ILiquidationRewards.sol";
import {ITokenOracle} from "../interfaces/ITokenOracle.sol";
import {PercentageMath} from "../libraries/math/PercentageMath.sol";
import {IAddressesProvider} from "../interfaces/IAddressesProvider.sol";
import {ConfigTypes} from "../libraries/types/ConfigTypes.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {SafeERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import {IERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "hardhat/console.sol";

contract LiquidationRewards is
    Initializable,
    ILiquidationRewards,
    OwnableUpgradeable
{
    IAddressesProvider private _addressProvider;
    ConfigTypes.LiquidationRewardConfig internal _liquidatonRewardsConfig;

    //Reserves that have their liquidations incentivized
    mapping(address => bool) private _reserveIncentives;

    using SafeERC20Upgradeable for IERC20Upgradeable;

    modifier onlyMarket() {
        require(
            _msgSender() == _addressProvider.getMarket(),
            "Callers must be Market contract"
        );
        _;
    }

    function initialize(
        IAddressesProvider addressProvider,
        ConfigTypes.LiquidationRewardConfig calldata liquidatonRewardsConfig
    ) external initializer {
        __Ownable_init();
        _addressProvider = addressProvider;
        _liquidatonRewardsConfig = liquidatonRewardsConfig;
    }

    function isReserveLiquidationIncentivized(
        address reserve
    ) external view returns (bool) {
        return _reserveIncentives[reserve];
    }

    function setReserveLiquidationIncentives(
        address reserve,
        bool isIncentivized
    ) external onlyOwner {
        _reserveIncentives[reserve] = isIncentivized;
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
                    tokenOracle.getPricePrecision() ** 3) /
                (reserveTokenPrice *
                    tokenOracle.getTokenETHPrice(
                        _addressProvider.getNativeToken()
                    ) *
                    _liquidatonRewardsConfig.factor);

            // Set the maximum amount for a liquidation reward
            if (reward > _liquidatonRewardsConfig.maxReward) {
                reward = _liquidatonRewardsConfig.maxReward;
            }

            // If the vault does not have enough balance to cover the reward
            uint256 rewardVaultBalance = IERC20Upgradeable(
                _addressProvider.getNativeToken()
            ).balanceOf(address(this));
            if (reward > rewardVaultBalance) {
                reward = rewardVaultBalance;
            }
        }

        return reward;
    }

    function sendLiquidationReward(
        address liquidator,
        uint256 amount
    ) external override onlyMarket {
        IERC20Upgradeable(_addressProvider.getNativeToken()).safeTransfer(
            liquidator,
            amount
        );
    }

    function getLiquidationRewardPriceLimit() external view returns (uint256) {
        return _liquidatonRewardsConfig.priceLimit;
    }

    function setLiquidationRewardPriceLimit(
        uint256 liquidationRewardPriceLimit
    ) external onlyOwner {
        _liquidatonRewardsConfig.priceLimit = liquidationRewardPriceLimit;
    }

    function getLiquidationRewardFactor() external view returns (uint256) {
        return _liquidatonRewardsConfig.factor;
    }

    function setLiquidationRewardFactor(
        uint256 liquidationRewardFactor
    ) external onlyOwner {
        _liquidatonRewardsConfig.factor = liquidationRewardFactor;
    }

    function getMaxLiquidationReward() external view returns (uint256) {
        return _liquidatonRewardsConfig.maxReward;
    }

    function setMaxLiquidationReward(
        uint256 maxLiquidationReward
    ) external onlyOwner {
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
}
