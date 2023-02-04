//SPDX-License-Identifier: Unlicense
pragma solidity 0.8.17;

import {Trustus} from "../../protocol/Trustus/Trustus.sol";

library DataTypes {
    struct TokenPrice {
        address collection;
        uint256 tokenId;
        uint256 amount;
    }

    struct LiquidityPair {
        uint256[] nftIds;
        uint256 tokenAmount;
        uint256 price;
        address curve;
        uint256 delta;
        uint256 fee;
    }

    struct NftToLp {
        uint256 liquidityPair;
        uint256 index;
    }

    struct AirdropTokens {
        address user;
        uint256 amount;
    }

    struct WorkingBalance {
        uint256 amount;
        uint256 timestamp;
    }

    struct LockedBalance {
        uint256 amount;
        uint256 end;
    }

    struct Point {
        uint256 bias;
        uint256 slope;
        uint256 timestamp;
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
        // address of lending pool associated with loan
        address pool;
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
        uint256 lpAmount;
        bool mintedRewards;
    }

    struct BorrowParams {
        address caller;
        address onBehalfOf;
        address asset;
        uint256 amount;
        address nftAddress;
        uint256 nftTokenID;
        uint256 genesisNFTId;
        bytes32 request;
        Trustus.TrustusPacket packet;
    }

    struct RepayParams {
        address caller;
        uint256 loanId;
        uint256 amount;
    }

    struct LiquidationParams {
        address caller;
        uint256 loanId;
        bytes32 request;
        Trustus.TrustusPacket packet;
    }
}
