// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.8.19;

import {DataTypes} from "../types/DataTypes.sol";
import {PercentageMath} from "../math/PercentageMath.sol";

library LoanLogic {
    function init(
        DataTypes.LoanData storage loandata,
        address pool,
        uint256 amount,
        uint256 genesisNFTId,
        address nftAsset,
        uint256[] memory nftTokenIds,
        uint256 borrowRate
    ) internal {
        loandata.state = DataTypes.LoanState.Created;
        loandata.amount = amount;
        loandata.genesisNFTId = genesisNFTId;
        loandata.nftAsset = nftAsset;
        loandata.nftTokenIds = nftTokenIds;
        loandata.borrowRate = uint16(borrowRate);
        loandata.pool = pool;
        loandata.initTimestamp = uint40(block.timestamp);
        loandata.debtTimestamp = uint40(block.timestamp);
    }

    function getInterest(
        DataTypes.LoanData storage loandata,
        uint256 timestamp
    ) internal view returns (uint256) {
        //Interest increases every 30 minutes
        uint256 incrementalTimestamp = (((timestamp - 1) / (30 * 60)) + 1) *
            (30 * 60);

        return
            (loandata.amount *
                loandata.borrowRate *
                (incrementalTimestamp - loandata.debtTimestamp)) /
            (PercentageMath.PERCENTAGE_FACTOR * 365 days);
    }
}
