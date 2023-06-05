// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.8.19;

import {DataTypes} from "../types/DataTypes.sol";
import {PercentageMath} from "../utils/PercentageMath.sol";
import {INFTOracle} from "../../interfaces/INFTOracle.sol";
import {ITokenOracle} from "../../interfaces/ITokenOracle.sol";
import {IInterestRate} from "../../interfaces/IInterestRate.sol";
import {IAddressProvider} from "../../interfaces/IAddressProvider.sol";
import {ILendingMarket} from "../../interfaces/ILendingMarket.sol";
import {ILoanCenter} from "../../interfaces/ILoanCenter.sol";
import {IGenesisNFT} from "../../interfaces/IGenesisNFT.sol";
import {ILendingPool} from "../../interfaces/ILendingPool.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";

/// @title ValidationLogic
/// @author leNFT
/// @notice Contains the logic for the lending validation functions
/// @dev Library dealing with the logic for the lending validation functions
library ValidationLogic {
    uint256 private constant LIQUIDATION_AUCTION_PERIOD = 3600 * 24;
    uint256 private constant MININUM_DEPOSIT_EMPTY_VAULT = 1e10;

    /// @notice Validates a deposit into a lending pool
    /// @param addressProvider The address of the addresses provider
    /// @param totalAssets The total assets of the pool
    /// @param totalShares The total shares of the pool
    /// @param amount The amount of tokens to deposit
    function validateDeposit(
        IAddressProvider addressProvider,
        uint256 totalAssets,
        uint256 totalShares,
        uint256 amount
    ) external view {
        // Check deposit amount. Minimum deposit is 1e10 if the vault is empty to avoid inflation attacks
        if (totalShares == 0) {
            require(amount >= MININUM_DEPOSIT_EMPTY_VAULT, "VL:VD:MIN_DEPOSIT");
        } else {
            require(amount > 0, "VL:VD:AMOUNT_0");
        }

        // Check if pool will exceed maximum permitted amount
        require(
            amount + totalAssets <
                ILendingMarket(addressProvider.getLendingMarket())
                    .getTVLSafeguard(),
            "VL:VD:SAFEGUARD_EXCEEDED"
        );
    }

    /// @notice Validates a withdraw from a lending pool
    /// @param addressProvider The address of the addresses provider
    /// @param maxUtilizationRate The maximum utilization rate of the pool
    /// @param debt The total debt of the pool
    /// @param underlyingBalance The underlying balance of the pool
    /// @param asset The address of the asset to withdraw
    /// @param amount The amount of tokens to withdraw
    function validateWithdrawal(
        IAddressProvider addressProvider,
        uint256 maxUtilizationRate,
        uint256 debt,
        uint256 underlyingBalance,
        address asset,
        uint256 amount
    ) external view {
        // Check if withdrawal amount is bigger than 0
        require(amount > 0, "VL:VW:AMOUNT_0");

        // Check if the utilization rate doesn't go above maximum
        require(
            IInterestRate(addressProvider.getInterestRate())
                .calculateUtilizationRate(
                    asset,
                    underlyingBalance - amount,
                    debt
                ) <= maxUtilizationRate,
            "VL:VW:MAX_UTILIZATION_RATE"
        );
    }

    /// @notice Validates a borrow from a lending pool
    /// @param addressProvider The address of the addresses provider
    /// @param lendingPool The address of the lending pool
    /// @param params The borrow params
    function validateBorrow(
        IAddressProvider addressProvider,
        address lendingPool,
        DataTypes.BorrowParams memory params
    ) external view {
        // Check if borrow amount is bigger than 0
        require(params.amount > 0, "VL:VB:AMOUNT_0");

        // Check if theres at least one asset to use as collateral
        require(params.nftTokenIds.length > 0, "VL:VB:NO_NFTS");

        // Check if the lending pool exists
        require(lendingPool != address(0), "VL:VB:INVALID_LENDING_POOL");

        // Get boost from genesis NFTs
        uint256 maxLTVBoost;
        if (params.genesisNFTId != 0) {
            IGenesisNFT genesisNFT = IGenesisNFT(
                addressProvider.getGenesisNFT()
            );

            // If the caller is not the user we are borrowing on behalf Of, check if the caller is approved
            if (params.onBehalfOf != params.caller) {
                require(
                    genesisNFT.isLoanOperatorApproved(
                        params.onBehalfOf,
                        params.caller
                    ),
                    "VL:VB:GENESIS_NOT_AUTHORIZED"
                );
            }
            require(
                genesisNFT.ownerOf(params.genesisNFTId) == params.onBehalfOf,
                "VL:VB:GENESIS_NOT_OWNED"
            );
            //Require that the NFT is not being used
            require(
                genesisNFT.getLockedState(params.genesisNFTId) == false,
                "VL:VB:GENESIS_LOCKED"
            );

            maxLTVBoost = genesisNFT.getMaxLTVBoost();
        }

        // Get assets ETH price
        ITokenOracle tokenOracle = ITokenOracle(
            addressProvider.getTokenOracle()
        );
        uint256 assetETHPrice = tokenOracle.getTokenETHPrice(params.asset);
        uint256 pricePrecision = tokenOracle.getPricePrecision();
        uint256 collateralETHPrice = INFTOracle(addressProvider.getNFTOracle())
            .getTokensETHPrice(
                params.nftAddress,
                params.nftTokenIds,
                params.request,
                params.packet
            );

        // Check if borrow amount exceeds allowed amount
        require(
            params.amount <=
                (PercentageMath.percentMul(
                    collateralETHPrice,
                    ILoanCenter(addressProvider.getLoanCenter())
                        .getCollectionMaxLTV(params.nftAddress) + maxLTVBoost
                ) * pricePrecision) /
                    assetETHPrice,
            "VL:VB:MAX_LTV_EXCEEDED"
        );

        // Check if the pool has enough underlying to borrow
        require(
            params.amount <= ILendingPool(lendingPool).getUnderlyingBalance(),
            "VL:VB:INSUFFICIENT_UNDERLYING"
        );
    }

    /// @notice Validates a repay of a loan
    /// @param params The repay params
    /// @param loanState The state of the loan
    /// @param loanDebt The debt of the loan
    function validateRepay(
        DataTypes.RepayParams memory params,
        DataTypes.LoanState loanState,
        uint256 loanDebt
    ) external pure {
        // Check if borrow amount is bigger than 0
        require(params.amount > 0, "VL:VR:AMOUNT_0");

        //Require that loan exists
        require(
            loanState == DataTypes.LoanState.Active ||
                loanState == DataTypes.LoanState.Auctioned,
            "VL:VR:LOAN_NOT_FOUND"
        );

        // Check if user is over-paying
        require(params.amount <= loanDebt, "VL:VR:AMOUNT_EXCEEDS_DEBT");

        // Can only do partial repayments if the loan is not being auctioned
        if (params.amount < loanDebt) {
            require(
                loanState != DataTypes.LoanState.Auctioned,
                "VL:VR:PARTIAL_REPAY_AUCTIONED"
            );
        }
    }

    /// @notice Validates a liquidation of a loan
    /// @param addressProvider The address of the addresses provider
    /// @param params The liquidation params
    /// @param loanState The state of the loan
    /// @param lendingPool The address of the lending pool of the loan
    /// @param loanNFTAsset The address of the NFT asset of the loan
    /// @param loanNFTTokenIds The token ids of the NFTs of the loan
    function validateCreateLiquidationAuction(
        IAddressProvider addressProvider,
        DataTypes.CreateAuctionParams memory params,
        DataTypes.LoanState loanState,
        address lendingPool,
        address loanNFTAsset,
        uint256[] calldata loanNFTTokenIds
    ) external view {
        //Require the loan exists
        require(
            loanState == DataTypes.LoanState.Active,
            "VL:VCLA:LOAN_NOT_FOUND"
        );

        // Check if collateral / debt relation allows for liquidation
        ITokenOracle tokenOracle = ITokenOracle(
            addressProvider.getTokenOracle()
        );
        uint256 assetETHPrice = tokenOracle.getTokenETHPrice(
            IERC4626(lendingPool).asset()
        );
        uint256 pricePrecision = tokenOracle.getPricePrecision();

        uint256 collateralETHPrice = INFTOracle(addressProvider.getNFTOracle())
            .getTokensETHPrice(
                loanNFTAsset,
                loanNFTTokenIds,
                params.request,
                params.packet
            );

        // Get loan center
        ILoanCenter loanCenter = ILoanCenter(addressProvider.getLoanCenter());

        require(
            (loanCenter.getLoanMaxDebt(params.loanId, collateralETHPrice) *
                pricePrecision) /
                assetETHPrice <
                loanCenter.getLoanDebt(params.loanId),
            "VL:VCLA:MAX_DEBT_NOT_EXCEEDED"
        );

        // Check if bid is large enough
        require(
            (assetETHPrice * params.bid) / pricePrecision >=
                PercentageMath.percentMul(
                    collateralETHPrice,
                    (PercentageMath.PERCENTAGE_FACTOR -
                        ILendingPool(lendingPool)
                            .getPoolConfig()
                            .maxLiquidatorDiscount)
                ),
            "VL:VCLA:BID_TOO_LOW"
        );
    }

    /// @notice Validates a bid on a liquidation auction
    /// @param params The bid params
    /// @param loanState  The state of the loan
    /// @param loanAuctionStartTimestamp The timestamp when the auction started
    /// @param loanAuctionMaxBid The current max bid of the auction
    function validateBidLiquidationAuction(
        DataTypes.BidAuctionParams memory params,
        DataTypes.LoanState loanState,
        uint256 loanAuctionStartTimestamp,
        uint256 loanAuctionMaxBid
    ) external view {
        // Check if the auction exists
        require(
            loanState == DataTypes.LoanState.Auctioned,
            "VL:VBLA:AUCTION_NOT_FOUND"
        );

        // Check if the auction is still active
        require(
            block.timestamp <
                loanAuctionStartTimestamp + LIQUIDATION_AUCTION_PERIOD,
            "VL:VBLA:AUCTION_NOT_ACTIVE"
        );

        // Check if bid is higher than current bid
        require(params.bid > loanAuctionMaxBid, "VL:VBLA:BID_TOO_LOW");
    }

    /// @notice Validates a claim of a liquidation auction
    /// @param loanState  The state of the loan
    /// @param loanAuctionStartTimestamp The timestamp when the auction started
    function validateClaimLiquidation(
        DataTypes.LoanState loanState,
        uint256 loanAuctionStartTimestamp
    ) external view {
        // Check if the loan is being auctioned
        require(
            loanState == DataTypes.LoanState.Auctioned,
            "VL:VCLA:AUCTION_NOT_FOUND"
        );

        // Check if the auction is still active
        require(
            block.timestamp >
                loanAuctionStartTimestamp + LIQUIDATION_AUCTION_PERIOD,
            "VL:VCLA:AUCTION_NOT_FINISHED"
        );
    }
}
