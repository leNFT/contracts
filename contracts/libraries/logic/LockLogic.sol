// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.8.19;

import {DataTypes} from "../types/DataTypes.sol";

/// @title LockLogic library
/// @author leNFT
/// @notice Defines the logic for a locked balance data type
/// @dev Library dealing with the logic for the locked balance data type
library LockLogic {
    /// @notice Initializes a locked balance
    /// @param lockedBalance The locked balance to initialize
    /// @param amount The amount to initialize the locked balance with
    /// @param end The end timestamp of the locked balance
    function init(
        DataTypes.LockedBalance storage lockedBalance,
        uint256 amount,
        uint256 end
    ) internal {
        lockedBalance.amount = amount;
        lockedBalance.end = end;
    }
}
