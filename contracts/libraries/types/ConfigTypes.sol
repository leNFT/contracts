//SPDX-License-Identifier: Unlicense
pragma solidity 0.8.17;

import {Trustus} from "../../protocol/Trustus/Trustus.sol";

library ConfigTypes {
    struct LendingPoolConfig {
        uint256 maxLiquidatorDiscount;
        uint256 auctionerFee;
        uint256 liquidationFee;
        uint256 maxUtilizationRate;
    }
}
