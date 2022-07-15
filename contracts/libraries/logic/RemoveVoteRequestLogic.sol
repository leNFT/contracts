// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.8.15;

import {DataTypes} from "../types/DataTypes.sol";

library RemoveVoteRequestLogic {
    function init(
        DataTypes.RemoveVoteRequest storage removeVoteRequest,
        address user,
        uint256 amount
    ) internal {
        removeVoteRequest.user = user;
        removeVoteRequest.amount = amount;
        removeVoteRequest.timestamp = block.timestamp;
    }
}
