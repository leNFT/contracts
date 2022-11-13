//SPDX-License-Identifier: Unlicense
pragma solidity 0.8.17;

import {Trustus} from "../../protocol/Trustus/Trustus.sol";

library DataTypes {
    struct WithdrawalRequest {
        bool created;
        uint256 amount;
        uint256 timestamp;
    }

    struct TokenPrice {
        address collection;
        uint256 tokenId;
        uint256 amount;
    }

    struct AirdropTokens {
        address user;
        uint256 amount;
    }

    /**
     * State change flow:
     * None -> Created -> Active -> Repaid -> Auction -> Defaulted
     * 0 - None (Default Value): We need a default that is not 'Created' - this is the zero value
     * 1 - Created: The loan data is stored; but not initiated yet.
     * 2 - Active: The loan has been initialized; funds have been delivered to the borrower and the collateral is held.
     * 3 - Repaid: The loan has been repaid; and the collateral has been returned to the borrower. This is a terminal state.
     * 4 - Defaulted: The loan was delinquent and collateral claimed by the liquidator. This is a terminal state.
     */
    enum LoanState {
        None,
        Created,
        Active,
        Repaid,
        Defaulted
    }

    struct LoanData {
        // the id of the loan
        uint256 loanId;
        // the current state of the loan
        LoanState state;
        // address of borrower
        address borrower;
        // borrowed amount
        uint256 amount;
        // maxLTV
        uint256 maxLTV;
        // ltv boost gotten through vote staking
        uint256 boost;
        // The boost given by the use of a genesis NFT
        uint256 genesisNFTId;
        // The boost given by the use of a genesis NFT
        uint256 genesisNFTBoost;
        // address of nft asset token
        address nftAsset;
        // the id of nft token
        uint256 nftTokenId;
        // address of reserve associated with loan
        address reserve;
        // interest rate at which the loan was written
        uint256 borrowRate;
        // timestamp for the initial creation of the loan
        uint256 initTimestamp;
        // timestamp for debt computation ()
        uint256 debtTimestamp;
    }

    // Mint details for the Genesis NFT mint
    struct MintDetails {
        uint256 timestamp;
        uint256 locktime;
    }

    struct BorrowParams {
        address initiator;
        address depositor;
        address asset;
        uint256 amount;
        address nftAddress;
        uint256 nftTokenID;
        uint256 genesisNFTId;
        bytes32 request;
        Trustus.TrustusPacket packet;
    }

    struct RepayParams {
        address initiator;
        uint256 loanId;
        uint256 amount;
    }

    struct LiquidationParams {
        address initiator;
        uint256 loanId;
        bytes32 request;
        Trustus.TrustusPacket packet;
    }
}
