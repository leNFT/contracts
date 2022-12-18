//SPDX-License-Identifier: Unlicense
pragma solidity 0.8.17;

import {Trustus} from "../../protocol/Trustus/Trustus.sol";

library ConfigTypes {
    struct LiquidationRewardConfig {
        uint256 factor;
        uint256 maxReward;
        uint256 priceThreshold;
        uint256 priceLimit;
    }

    struct LendingPoolConfig {
        uint256 liquidationPenalty;
        uint256 liquidationFee;
        uint256 maximumUtilizationRate;
        uint256 tvlSafeguard;
    }
}
