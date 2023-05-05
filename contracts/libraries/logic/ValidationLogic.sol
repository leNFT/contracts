// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.8.19;

import {DataTypes} from "../types/DataTypes.sol";
import {PercentageMath} from "../math/PercentageMath.sol";
import {INFTOracle} from "../../interfaces/INFTOracle.sol";
import {ITokenOracle} from "../../interfaces/ITokenOracle.sol";
import {IInterestRate} from "../../interfaces/IInterestRate.sol";
import {IAddressesProvider} from "../../interfaces/IAddressesProvider.sol";
import {ILendingMarket} from "../../interfaces/ILendingMarket.sol";
import {ILoanCenter} from "../../interfaces/ILoanCenter.sol";
import {IGenesisNFT} from "../../interfaces/IGenesisNFT.sol";
import {ILendingPool} from "../../interfaces/ILendingPool.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";

/// @title ValidationLogic
/// @notice Contains the logic for the lending validation functions
library ValidationLogic {
    uint256 constant LIQUIDATION_AUCTION_PERIOD = 3600 * 24;

    /// @notice Validates a deposit into a lending pool
    /// @param addressesProvider The address of the addresses provider
    /// @param lendingPool The address of the lending pool
    /// @param amount The amount of tokens to deposit
    function validateDeposit(
        IAddressesProvider addressesProvider,
        address lendingPool,
        uint256 amount
    ) external view {
        // Check if deposit amount is bigger than 0
        require(amount > 0, "Deposit amount must be bigger than 0");

        // Check if pool will exceed maximum permitted amount
        require(
            amount + IERC4626(lendingPool).totalAssets() <
                ILendingMarket(addressesProvider.getLendingMarket())
                    .getTVLSafeguard(),
            "Lending Pool exceeds safeguarded limit"
        );
    }

    /// @notice Validates a withdraw from a lending pool
    /// @param addressesProvider The address of the addresses provider
    /// @param lendingPool The address of the lending pool
    /// @param amount The amount of tokens to withdraw
    function validateWithdrawal(
        IAddressesProvider addressesProvider,
        address lendingPool,
        uint256 amount
    ) external view {
        // Check if the utilization rate doesn't go above maximum
        uint256 maxUtilizationRate = ILendingPool(lendingPool)
            .getPoolConfig()
            .maxUtilizationRate;
        uint256 debt = ILendingPool(lendingPool).getDebt();
        uint256 underlyingBalance = ILendingPool(lendingPool)
            .getUnderlyingBalance();
        uint256 updatedUtilizationRate = IInterestRate(
            addressesProvider.getInterestRate()
        ).calculateUtilizationRate(
                IERC4626(lendingPool).asset(),
                underlyingBalance - amount,
                debt
            );

        require(
            updatedUtilizationRate <= maxUtilizationRate,
            "Reserve utilization rate too high"
        );

        // Check if withdrawal amount is bigger than 0
        require(amount > 0, "Withdrawal amount must be bigger than 0");
    }

    /// @notice Validates a borrow from a lending pool
    /// @param addressesProvider The address of the addresses provider
    /// @param lendingPools The address of the lending pools
    /// @param params The borrow params
    function validateBorrow(
        IAddressesProvider addressesProvider,
        mapping(address => mapping(address => address)) storage lendingPools,
        DataTypes.BorrowParams memory params
    ) external view {
        // Check if borrow amount is bigger than 0
        require(params.amount > 0, "Borrow amount must be bigger than 0");

        // Check if theres at least one asset
        require(
            params.nftTokenIds.length > 0,
            "No assets provided as collateral"
        );

        // Check if the asset is supported
        require(
            lendingPools[params.nftAddress][params.asset] != address(0),
            "No pool for asset and collection"
        );

        ITokenOracle tokenOracle = ITokenOracle(
            addressesProvider.getTokenOracle()
        );
        uint256 assetETHPrice = tokenOracle.getTokenETHPrice(params.asset);
        uint256 pricePrecision = tokenOracle.getPricePrecision();

        // Get boost from genesis NFTs
        uint256 boost;
        if (params.genesisNFTId != 0) {
            IGenesisNFT genesisNFT = IGenesisNFT(
                addressesProvider.getGenesisNFT()
            );

            // If the caller is not the user we are borrowing on behalf Of, check if the caller is approved
            if (params.onBehalfOf != params.caller) {
                require(
                    genesisNFT.isLoanOperatorApproved(
                        params.onBehalfOf,
                        params.caller
                    ),
                    "Not approved to borrow on behalf of"
                );
            }
            require(
                genesisNFT.ownerOf(params.genesisNFTId) == params.onBehalfOf,
                "Borrower doesn't own the Genesis NFT"
            );
            //Require that the NFT is not being used
            require(
                genesisNFT.getLockedState(params.genesisNFTId) == false,
                "Genesis NFT currently being used by another loan"
            );

            boost = genesisNFT.getLTVBoost();
        }

        // Get assets ETH price
        uint256 collateralETHPrice = INFTOracle(
            addressesProvider.getNFTOracle()
        ).getTokensETHPrice(
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
                    ILoanCenter(addressesProvider.getLoanCenter())
                        .getCollectionMaxCollaterization(params.nftAddress) +
                        boost
                ) * pricePrecision) /
                    assetETHPrice,
            "Amount exceeds allowed by collateral"
        );

        // Check if the pool has enough underlying to borrow
        require(
            params.amount <=
                ILendingPool(lendingPools[params.nftAddress][params.asset])
                    .getUnderlyingBalance(),
            "Amount exceeds pool balance"
        );
    }

    /// @notice Validates a repay of a loan
    /// @param params The repay params
    function validateRepay(
        DataTypes.RepayParams memory params,
        DataTypes.LoanState loanState,
        uint256 loanDebt
    ) external pure {
        // Check if borrow amount is bigger than 0
        require(params.amount > 0, "Repay amount must be bigger than 0");

        //Require that loan exists
        require(loanState != DataTypes.LoanState.None, "Loan does not exist");

        // Check if user is over paying
        require(
            params.amount <= loanDebt,
            "Overpaying in repay. Amount is bigger than debt."
        );

        // Can only do partial repayments if the loan is not being auctioned
        if (params.amount < loanDebt) {
            require(
                loanState != DataTypes.LoanState.Auctioned,
                "Cannot partially repay a loan that is being auctioned"
            );
        }
    }

    /// @notice Validates a liquidation of a loan
    /// @param addressesProvider The address of the addresses provider
    /// @param params The liquidation params
    function validateCreateLiquidationAuction(
        IAddressesProvider addressesProvider,
        DataTypes.CreateAuctionParams memory params,
        DataTypes.LoanState loanState,
        address loanPool,
        address loanNFTAsset,
        uint256[] calldata loanNFTTokenIds
    ) external view {
        //Require the loan exists
        require(loanState == DataTypes.LoanState.Active, "Loan is not active");

        // Check if collateral / debt relation allows for liquidation
        address poolAsset = IERC4626(loanPool).asset();
        ITokenOracle tokenOracle = ITokenOracle(
            addressesProvider.getTokenOracle()
        );
        uint256 assetETHPrice = tokenOracle.getTokenETHPrice(poolAsset);
        uint256 pricePrecision = tokenOracle.getPricePrecision();

        // Get loan center
        ILoanCenter loanCenter = ILoanCenter(addressesProvider.getLoanCenter());

        require(
            (loanCenter.getLoanMaxETHCollateral(
                params.loanId,
                params.request,
                params.packet
            ) * pricePrecision) /
                assetETHPrice <
                loanCenter.getLoanDebt(params.loanId),
            "Collateral / Debt loan relation does not allow for liquidation."
        );

        // Check if bid is big enough
        uint256 maxLiquidatorDiscount = ILendingPool(loanPool)
            .getPoolConfig()
            .maxLiquidatorDiscount;
        uint256 collateralETHPrice = INFTOracle(
            addressesProvider.getNFTOracle()
        ).getTokensETHPrice(
                loanNFTAsset,
                loanNFTTokenIds,
                params.request,
                params.packet
            );
        require(
            params.bid >=
                (collateralETHPrice *
                    (PercentageMath.PERCENTAGE_FACTOR -
                        maxLiquidatorDiscount)) /
                    PercentageMath.PERCENTAGE_FACTOR,
            "Bid amount is not big enough"
        );
    }

    function validateBidLiquidationAuction(
        DataTypes.AuctionBidParams memory params,
        DataTypes.LoanState loanState,
        uint256 loanAuctionStartTimestamp,
        uint256 loanAuctionMaxBid
    ) external view {
        // Check if the auction exists
        require(
            loanState == DataTypes.LoanState.Auctioned,
            "No liquidation auction for this loan"
        );

        // Check if the auction is still active
        require(
            block.timestamp <
                loanAuctionStartTimestamp + LIQUIDATION_AUCTION_PERIOD,
            "Auction is no longer active"
        );

        // Check if bid is higher than current bid
        require(
            params.bid > loanAuctionMaxBid,
            "Bid amount is not higher than current bid"
        );
    }

    function validateClaimLiquidation(
        DataTypes.LoanState loanState,
        uint256 loanAuctionStartTimestamp
    ) external view {
        // Check if the auction exists
        require(
            loanState == DataTypes.LoanState.Auctioned,
            "No liquidation auction for this loan"
        );

        // Check if the auction is still active
        require(
            block.timestamp >
                loanAuctionStartTimestamp + LIQUIDATION_AUCTION_PERIOD,
            "Auction is still active"
        );
    }
}
