// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.8.15;

import {DataTypes} from "../types/DataTypes.sol";
import {PercentageMath} from "../math/PercentageMath.sol";

library LoanLogic {
    uint256 constant ONE_YEAR = 31536000;

    function init(
        DataTypes.LoanData storage loandata,
        uint256 loanId,
        address borrower,
        address reserveAsset,
        uint256 amount,
        address nftAsset,
        uint256 nftTokenId,
        uint256 borrowRate
    ) internal {
        loandata.loanId = loanId;
        loandata.state = DataTypes.LoanState.Created;
        loandata.borrower = borrower;
        loandata.amount = amount;
        loandata.nftAsset = nftAsset;
        loandata.nftTokenId = nftTokenId;
        loandata.borrowRate = borrowRate;
        loandata.reserveAsset = reserveAsset;
        loandata.initTimestamp = block.timestamp;
    }

    function getInterest(DataTypes.LoanData storage loandata, uint256 timestamp)
        internal
        view
        returns (uint256)
    {
        uint256 timeSpentInYears = (timestamp - loandata.initTimestamp) /
            ONE_YEAR;

        return PercentageMath.percentMul(timeSpentInYears, loandata.borrowRate);
    }
}
