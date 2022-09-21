//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;

library DataTypes {
    struct CollectionData {
        bool supported;
        uint256 maxCollaterization;
        uint256 lastUpdateTimestamp;
    }

    struct WithdrawRequest {
        bool created;
        uint256 amount;
        uint256 timestamp;
    }

    struct TokenPrice {
        address collection;
        uint256 tokenId;
        uint256 amount;
    }

    /**
     * State change flow:
     * None -> Created -> Active -> Repaid -> Auction -> Defaulted
     * None (Default Value): We need a default that is not 'Created' - this is the zero value
     * Created: The loan data is stored, but not initiated yet.
     * Active: The loan has been initialized, funds have been delivered to the borrower and the collateral is held.
     * Repaid: The loan has been repaid, and the collateral has been returned to the borrower. This is a terminal state.
     * Defaulted: The loan was delinquent and collateral claimed by the liquidator. This is a terminal state.
     */
    enum LoanState {
        None,
        Created,
        Active,
        Repaid,
        Defaulted
    }

    struct LoanData {
        //the id of the loan
        uint256 loanId;
        //the current state of the loan
        LoanState state;
        //address of borrower
        address borrower;
        //borrowed amount
        uint256 amount;
        //ltv boost gotten through vote staking
        uint256 boost;
        //address of nft asset token
        address nftAsset;
        //the id of nft token
        uint256 nftTokenId;
        //address of reserve associated with loan
        address reserve;
        // interest rate at which the loan was written
        uint256 borrowRate;
        // timestamp of the initial creation of the loan
        uint256 initTimestamp;
    }
}
