// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.8.15;

import {DataTypes} from "../types/DataTypes.sol";
import {PercentageMath} from "../math/PercentageMath.sol";

import "hardhat/console.sol";

library LoanLogic {
    function init(
        DataTypes.LoanData storage loandata,
        uint256 loanId,
        address borrower,
        address reserve,
        uint256 amount,
        uint256 maxLTV,
        uint256 boost,
        uint256 genesisNFTId,
        address nftAsset,
        uint256 nftTokenId,
        uint256 borrowRate
    ) internal {
        loandata.loanId = loanId;
        loandata.state = DataTypes.LoanState.Created;
        loandata.borrower = borrower;
        loandata.amount = amount;
        loandata.maxLTV = maxLTV;
        loandata.boost = boost;
        loandata.genesisNFTId = genesisNFTId;
        loandata.nftAsset = nftAsset;
        loandata.nftTokenId = nftTokenId;
        loandata.borrowRate = borrowRate;
        loandata.reserve = reserve;
        loandata.initTimestamp = block.timestamp;
        loandata.debtTimestamp = block.timestamp;
    }

    function getInterest(DataTypes.LoanData storage loandata, uint256 timestamp)
        internal
        view
        returns (uint256)
    {
        //Interest increases every 10 minutes
        uint256 incrementalTimestamp = (timestamp / 600) * 601;
        return
            (loandata.amount *
                loandata.borrowRate *
                (incrementalTimestamp - loandata.debtTimestamp)) /
            (PercentageMath.PERCENTAGE_FACTOR * 365 days);
    }
}
