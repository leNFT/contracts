//SPDX-License-Identifier: Unlicense
pragma solidity 0.8.19;

import {Trustus} from "../../protocol/Trustus/Trustus.sol";

library DataTypes {
    struct AssetsPrice {
        address collection;
        uint256[] tokenIds;
        uint256 amount;
    }

    struct CollectionRiskParameters {
        uint16 maxLTV;
        uint16 liquidationThreshold;
    }

    /**
     * Liquidity Pair Types:
     * 0 - Trade: Can buy and sell and price can increase and decrease
     * 1 - TradeUp: Can buy and sell and price can only increase
     * 2 - TradeDown: Can buy and sell and price can only decrease
     * 3 - Buy: Can only buy (price will only decrease)
     * 4 - Sell: Can only sell (price will only increase)
     */
    enum LPType {
        Trade,
        TradeUp,
        TradeDown,
        Buy,
        Sell
    }

    struct LiquidityPair {
        LPType lpType;
        uint256[] nftIds;
        uint256 tokenAmount;
        uint256 spotPrice;
        address curve;
        uint256 delta;
        uint256 fee;
    }

    struct NftToLp {
        uint256 liquidityPair;
        uint256 index;
    }

    struct WorkingBalance {
        uint256 amount;
        uint256 weight;
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
     * None -> Created -> Active -> Repaid -> Auction -> Liquidated
     * 0 - None (Default Value): We need a default that is not 'Created' - this is the zero value
     * 1 - Created: The loan data is stored; but not initiated yet.
     * 2 - Active: The loan has been initialized; funds have been delivered to the borrower and the collateral is held.
     * 3 - Repaid: The loan has been repaid; and the collateral has been returned to the borrower. This can be a terminal state.
     * 4 - Actioned: The loan's collateral has been auctioned off and its in the process of being liquidated.
     * 5 - Liquidated: The loan's collateral was claimed by the liquidator. This is a terminal state.
     */
    enum LoanState {
        None,
        Created,
        Active,
        Repaid,
        Auctioned,
        Liquidated
    }

    struct LoanData {
        // owner of the loan
        address owner;
        // borrowed amount
        uint256 amount;
        // the ids of the token
        uint256[] nftTokenIds;
        // address of nft asset token
        address nftAsset;
        // interest rate at which the loan was written
        uint16 borrowRate;
        // timestamp for the initial creation of the loan
        uint40 initTimestamp;
        // timestamp for debt computation
        uint40 debtTimestamp;
        // address of lending pool associated with loan
        address pool;
        // The genesis NFT id for the boost (0 if not used). uint16 is used since genesis cap < 65536
        uint16 genesisNFTId;
        // the current state of the loan
        LoanState state;
    }

    struct LoanLiquidationData {
        // address of the user who first auctioned the loan
        address auctioner;
        // address of the liquidator withe highest bid
        address liquidator;
        // timestamp of the liquidation auction start
        uint40 auctionStartTimestamp;
        // highes liquidation auction bid
        uint256 auctionMaxBid;
    }

    // Mint details for the Genesis NFT mint
    struct MintDetails {
        uint256 timestamp;
        uint256 locktime;
        uint256 lpAmount;
    }

    struct BorrowParams {
        address caller;
        address onBehalfOf;
        address asset;
        uint256 amount;
        address nftAddress;
        uint256[] nftTokenIds;
        uint256 genesisNFTId;
        bytes32 request;
        Trustus.TrustusPacket packet;
    }

    struct RepayParams {
        address caller;
        uint256 loanId;
        uint256 amount;
    }

    struct CreateAuctionParams {
        address caller;
        uint256 loanId;
        uint256 bid;
        bytes32 request;
        Trustus.TrustusPacket packet;
    }

    struct AuctionBidParams {
        address caller;
        uint256 loanId;
        uint256 bid;
    }

    struct ClaimLiquidationParams {
        uint256 loanId;
    }

    struct VestingParams {
        uint256 timestamp;
        uint256 period;
        uint256 cliff;
        uint256 amount;
    }

    struct BalancerDetails {
        bytes32 poolId;
        address pool;
        address vault;
        address queries;
    }
}
