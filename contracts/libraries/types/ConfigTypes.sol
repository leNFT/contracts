//SPDX-License-Identifier: Unlicense
pragma solidity 0.8.17;

import {Trustus} from "../../protocol/Trustus/Trustus.sol";

library ConfigTypes {
    struct BoostConfig {
        uint256 factor;
        uint256 limit;
    }

    struct LiquidationRewardConfig {
        uint256 factor;
        uint256 maxReward;
        uint256 priceThreshold;
        uint256 priceLimit;
    }

    struct StakingRewardConfig {
        uint256 factor;
        uint256 period;
        uint256 maxPeriods;
    }

    struct NativeTokenWithdrawalConfig {
        uint256 coolingPeriod;
        uint256 activePeriod;
    }

    struct ReserveConfig {
        uint256 liquidationPenalty;
        uint256 protocolLiquidationFee;
        uint256 maximumUtilizationRate;
        uint256 tvlSafeguard;
    }
}
