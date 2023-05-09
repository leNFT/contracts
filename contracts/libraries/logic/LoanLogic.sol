// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.8.19;

import {DataTypes} from "../types/DataTypes.sol";
import {PercentageMath} from "../math/PercentageMath.sol";

library LoanLogic {
    function init(
        DataTypes.LoanData storage loanData,
        address owner,
        address pool,
        uint256 amount,
        uint256 genesisNFTId,
        address nftAsset,
        uint256[] memory nftTokenIds,
        uint256 borrowRate
    ) internal {
        loanData.owner = owner;
        loanData.state = DataTypes.LoanState.Created;
        loanData.amount = amount;
        loanData.genesisNFTId = uint16(genesisNFTId);
        loanData.nftAsset = nftAsset;
        loanData.nftTokenIds = nftTokenIds;
        loanData.borrowRate = uint16(borrowRate);
        loanData.pool = pool;
        loanData.initTimestamp = uint40(block.timestamp);
        loanData.debtTimestamp = uint40(block.timestamp);
    }

    function getInterest(
        DataTypes.LoanData storage loanData,
        uint256 timestamp
    ) internal view returns (uint256) {
        //Interest increases every 30 minutes
        uint256 incrementalTimestamp = (((timestamp - 1) / (30 * 60)) + 1) *
            (30 * 60);

        return
            (loanData.amount *
                uint256(loanData.borrowRate) *
                (incrementalTimestamp - uint256(loanData.debtTimestamp))) /
            (PercentageMath.PERCENTAGE_FACTOR * 365 days);
    }
}
