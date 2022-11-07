// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.8.17;

import {DataTypes} from "../types/DataTypes.sol";

library WithdrawalRequestLogic {
    function init(
        DataTypes.WithdrawalRequest storage withdrawalRequest,
        uint256 amount
    ) internal {
        withdrawalRequest.created = true;
        withdrawalRequest.amount = amount;
        withdrawalRequest.timestamp = block.timestamp;
    }
}
