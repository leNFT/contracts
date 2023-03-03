// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.8.19;

import {DataTypes} from "../types/DataTypes.sol";

library LockLogic {
    function init(
        DataTypes.LockedBalance storage lockedBalance,
        uint256 amount,
        uint256 end
    ) internal {
        lockedBalance.amount = amount;
        lockedBalance.end = end;
    }
}
