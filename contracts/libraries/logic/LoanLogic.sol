// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.8.19;

import {DataTypes} from "../types/DataTypes.sol";
import {PercentageMath} from "../utils/PercentageMath.sol";
import {SafeCast} from "../utils/SafeCast.sol";

/// @title LoanLogic library
/// @notice Defines the logic for a loan data type
library LoanLogic {
    /// @notice Initializes a loan
    /// @param loanData A pointer to the loan data we want to initialize
    /// @param owner The owner of the loan
    /// @param pool The pool that the loan belongs to
    /// @param amount The amount borrowed
    /// @param genesisNFTId The genesis NFT ID associated with the loan
    /// @param nftAsset The NFT asset address
    /// @param nftTokenIds The NFT token IDs
    /// @param borrowRate The borrow rate associated with the loan
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
        loanData.genesisNFTId = SafeCast.toUint16(genesisNFTId);
        loanData.nftAsset = nftAsset;
        loanData.nftTokenIds = nftTokenIds;
        loanData.borrowRate = SafeCast.toUint16(borrowRate);
        loanData.pool = pool;
        loanData.initTimestamp = SafeCast.toUint40(block.timestamp);
        loanData.debtTimestamp = SafeCast.toUint40(block.timestamp);
    }

    /// @notice Internal function calculate the interest a loan has accrued
    /// @param loanData The loan data
    /// @param timestamp The timestamp to calculate the interest for
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
