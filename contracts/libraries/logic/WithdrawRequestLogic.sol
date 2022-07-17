// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.8.15;

import {DataTypes} from "../types/DataTypes.sol";

library WithdrawRequestLogic {
    function init(
        DataTypes.WithdrawRequest storage withdrawRequest,
        uint256 amount
    ) internal {
        withdrawRequest.amount = amount;
        withdrawRequest.timestamp = block.timestamp;
    }
}
