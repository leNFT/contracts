// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.8.15;

import {DataTypes} from "../types/DataTypes.sol";
import {PercentageMath} from "../math/PercentageMath.sol";

import "hardhat/console.sol";

library LoanLogic {
    uint256 internal constant ONE_YEAR = 31536000;
    uint256 internal constant PRECISION = 1e8;

    function init(
        DataTypes.LoanData storage loandata,
        uint256 loanId,
        address borrower,
        address reserve,
        uint256 amount,
        uint256 boost,
        address nftAsset,
        uint256 nftTokenId,
        uint256 borrowRate
    ) internal {
        loandata.loanId = loanId;
        loandata.state = DataTypes.LoanState.Created;
        loandata.borrower = borrower;
        loandata.amount = amount;
        loandata.boost = boost;
        loandata.nftAsset = nftAsset;
        loandata.nftTokenId = nftTokenId;
        loandata.borrowRate = borrowRate;
        loandata.reserve = reserve;
        loandata.initTimestamp = block.timestamp;
    }

    function getInterest(DataTypes.LoanData storage loandata, uint256 timestamp)
        internal
        view
        returns (uint256)
    {
        uint256 timeSpentInYears = (
            ((timestamp - loandata.initTimestamp) * PRECISION)
        ) / ONE_YEAR;

        uint256 accruedInterest = (loandata.borrowRate * timeSpentInYears) /
            PercentageMath.PERCENTAGE_FACTOR;

        return (loandata.amount * accruedInterest) / PRECISION;
    }
}
