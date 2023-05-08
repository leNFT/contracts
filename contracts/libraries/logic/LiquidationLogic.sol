// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.8.19;

import {DataTypes} from "../types/DataTypes.sol";
import {PercentageMath} from "../math/PercentageMath.sol";
import {ValidationLogic} from "./ValidationLogic.sol";
import {IAddressesProvider} from "../../interfaces/IAddressesProvider.sol";
import {IFeeDistributor} from "../../interfaces/IFeeDistributor.sol";
import {ILoanCenter} from "../../interfaces/ILoanCenter.sol";
import {ILendingPool} from "../../interfaces/ILendingPool.sol";
import {IDebtToken} from "../../interfaces/IDebtToken.sol";
import {IGenesisNFT} from "../../interfaces/IGenesisNFT.sol";
import {IERC721Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC721/IERC721Upgradeable.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {IERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import {SafeERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";

/// @title LiquidationLogic
/// @notice Contains the logic for the liquidate function
library LiquidationLogic {
    using SafeERC20Upgradeable for IERC20Upgradeable;

    /// @notice Liquidates a loan
    /// @param addressesProvider The address of the addresses provider
    /// @param params A struct with the parameters of the liquidate function
    function createLiquidationAuction(
        IAddressesProvider addressesProvider,
        DataTypes.CreateAuctionParams memory params
    ) external {
        // Get loan center
        ILoanCenter loanCenter = ILoanCenter(addressesProvider.getLoanCenter());
        // Get the loan
        DataTypes.LoanData memory loanData = loanCenter.getLoan(params.loanId);

        // Verify if liquidation conditions are met
        ValidationLogic.validateCreateLiquidationAuction(
            addressesProvider,
            params,
            loanData.state,
            loanData.pool,
            loanData.nftAsset,
            loanData.nftTokenIds
        );

        // Add auction to the loan
        loanCenter.auctionLoan(params.loanId, params.caller, params.bid);

        // Get the payment from the bidder
        IERC20Upgradeable(IERC4626(loanData.pool).asset()).safeTransferFrom(
            params.caller,
            address(this),
            params.bid
        );
    }

    function bidLiquidationAuction(
        IAddressesProvider addressesProvider,
        DataTypes.AuctionBidParams memory params
    ) external {
        // Get the loan center
        ILoanCenter loanCenter = ILoanCenter(addressesProvider.getLoanCenter());
        // Get the loan
        DataTypes.LoanData memory loanData = loanCenter.getLoan(params.loanId);
        // Get the loan liquidation data
        DataTypes.LoanLiquidationData memory loanLiquidationData = loanCenter
            .getLoanLiquidationData(params.loanId);

        // Verify if bid conditions are met
        ValidationLogic.validateBidLiquidationAuction(
            params,
            loanData.state,
            loanLiquidationData.auctionStartTimestamp,
            loanLiquidationData.auctionMaxBid
        );

        // Get the address of this asset's lending pool
        address poolAsset = IERC4626(loanData.pool).asset();

        // Send the old liquidator their funds back
        IERC20Upgradeable(poolAsset).safeTransfer(
            loanLiquidationData.liquidator,
            loanLiquidationData.auctionMaxBid
        );

        // Update the auction bid
        loanCenter.updateLoanAuctionBid(
            params.loanId,
            params.caller,
            params.bid
        );

        // Get the payment from the liquidator
        IERC20Upgradeable(poolAsset).safeTransferFrom(
            params.caller,
            address(this),
            params.bid
        );
    }

    function claimLiquidation(
        IAddressesProvider addressesProvider,
        DataTypes.ClaimLiquidationParams memory params
    ) external {
        // Get the loan center
        ILoanCenter loanCenter = ILoanCenter(addressesProvider.getLoanCenter());
        // Get the loan
        DataTypes.LoanData memory loanData = loanCenter.getLoan(params.loanId);
        // Get the loan liquidation data
        DataTypes.LoanLiquidationData memory loanLiquidationData = loanCenter
            .getLoanLiquidationData(params.loanId);

        // Verify if claim conditions are met
        ValidationLogic.validateClaimLiquidation(
            loanData.state,
            loanLiquidationData.auctionStartTimestamp
        );

        // Get the address of this asset's pool
        address poolAsset = IERC4626(loanData.pool).asset();
        // Repay loan...
        uint256 fundsLeft = loanLiquidationData.auctionMaxBid;
        uint256 loanInterest = loanCenter.getLoanInterest(params.loanId);
        uint256 loanDebt = loanData.amount + loanInterest;
        // If we only have funds to pay back part of the loan
        if (fundsLeft < loanDebt) {
            ILendingPool(loanData.pool).receiveUnderlyingDefaulted(
                address(this),
                fundsLeft,
                uint256(loanData.borrowRate),
                loanData.amount
            );

            fundsLeft = 0;
            // If we have funds to cover the whole debt associated with the loan
        } else {
            ILendingPool(loanData.pool).receiveUnderlying(
                address(this),
                loanData.amount,
                uint256(loanData.borrowRate),
                loanInterest
            );

            fundsLeft -= loanDebt;
        }

        // ... then get the protocol liquidation fee (if there are still funds available) ...
        if (fundsLeft > 0) {
            uint256 protocolFee = PercentageMath.percentMul(
                loanLiquidationData.auctionMaxBid,
                ILendingPool(loanData.pool).getPoolConfig().liquidationFee
            );
            if (protocolFee > fundsLeft) {
                protocolFee = fundsLeft;
            }
            IERC20Upgradeable(poolAsset).safeTransfer(
                addressesProvider.getFeeDistributor(),
                protocolFee
            );
            IFeeDistributor(addressesProvider.getFeeDistributor()).checkpoint(
                poolAsset
            );
            fundsLeft -= protocolFee;
        }

        // ... and the rest to the borrower.
        if (fundsLeft > 0) {
            IERC20Upgradeable(poolAsset).safeTransfer(
                IERC721Upgradeable(addressesProvider.getDebtToken()).ownerOf(
                    params.loanId
                ),
                fundsLeft
            );
        }

        // Update the state of the loan
        loanCenter.liquidateLoan(params.loanId);

        // Send collateral to liquidator
        for (uint i = 0; i < loanData.nftTokenIds.length; i++) {
            IERC721Upgradeable(loanData.nftAsset).safeTransferFrom(
                address(loanCenter),
                loanLiquidationData.liquidator,
                loanData.nftTokenIds[i]
            );
        }

        // Unlock Genesis NFT for use
        if (loanData.genesisNFTId != 0) {
            // Unlock Genesis NFT
            IGenesisNFT(addressesProvider.getGenesisNFT()).setLockedState(
                uint256(loanData.genesisNFTId),
                false
            );
        }

        // Burn the token representing the debt
        IDebtToken(addressesProvider.getDebtToken()).burn(params.loanId);
    }
}
