// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.8.19;

import {DataTypes} from "../types/DataTypes.sol";
import {PercentageMath} from "../utils/PercentageMath.sol";
import {ValidationLogic} from "./ValidationLogic.sol";
import {IAddressProvider} from "../../interfaces/IAddressProvider.sol";
import {ILoanCenter} from "../../interfaces/ILoanCenter.sol";
import {ILendingPool} from "../../interfaces/ILendingPool.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {IGenesisNFT} from "../../interfaces/IGenesisNFT.sol";
import {IERC721Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC721/IERC721Upgradeable.sol";
import {IERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import {SafeERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";

/// @title BorrowLogic
/// @author leNFT
/// @notice Contains the logic for the borrow and repay functions
/// @dev Library dealing with the logic for the borrow and repay functions
library BorrowLogic {
    using SafeERC20Upgradeable for IERC20Upgradeable;

    /// @notice Creates a new loan, transfers the collateral to the loan center and mints the debt token
    /// @param addressProvider The address of the addresses provider
    /// @param lendingPool The address of the lending pool
    /// @param params A struct with the parameters of the borrow function
    /// @return loanId The id of the new loan
    function borrow(
        IAddressProvider addressProvider,
        address lendingPool,
        DataTypes.BorrowParams memory params
    ) external returns (uint256 loanId) {
        // Validate the movement
        ValidationLogic.validateBorrow(addressProvider, lendingPool, params);

        // Get the loan center
        ILoanCenter loanCenter = ILoanCenter(addressProvider.getLoanCenter());

        // Transfer the collateral to the loan center
        for (uint256 i = 0; i < params.nftTokenIds.length; i++) {
            IERC721Upgradeable(params.nftAddress).safeTransferFrom(
                params.caller,
                address(loanCenter),
                params.nftTokenIds[i]
            );
        }

        // If a genesis NFT was used with this loan we need to lock it
        if (params.genesisNFTId != 0) {
            // Lock genesis NFT
            IGenesisNFT(addressProvider.getGenesisNFT()).setLockedState(
                params.genesisNFTId,
                true
            );
        }

        // Get the current borrow rate index
        uint256 borrowRate = ILendingPool(lendingPool).getBorrowRate();

        // Create the loan
        loanId = loanCenter.createLoan(
            params.onBehalfOf,
            lendingPool,
            params.amount,
            params.genesisNFTId,
            params.nftAddress,
            params.nftTokenIds,
            borrowRate
        );

        // Activate the loan
        loanCenter.activateLoan(loanId);

        // Send the principal to the borrower
        ILendingPool(lendingPool).transferUnderlying(
            params.caller,
            params.amount,
            borrowRate
        );
    }

    /// @notice Repays a loan, transfers the principal and interest to the lending pool and returns the collateral to the owner
    /// @param addressProvider The address of the addresses provider
    /// @param params A struct with the parameters of the repay function
    function repay(
        IAddressProvider addressProvider,
        DataTypes.RepayParams memory params
    ) external {
        // Get the loan
        ILoanCenter loanCenter = ILoanCenter(addressProvider.getLoanCenter());
        DataTypes.LoanData memory loanData = loanCenter.getLoan(params.loanId);
        uint256 interest = loanCenter.getLoanInterest(params.loanId);
        uint256 loanDebt = interest + loanData.amount;

        // Validate the movement
        ValidationLogic.validateRepay(params, loanData.state, loanDebt);

        // If we are paying the entire loan debt
        if (params.amount == loanDebt) {
            // If the loan was being liquidated we send the liquidators payment back with a fee
            if (loanData.state == DataTypes.LoanState.Auctioned) {
                address asset = IERC4626(loanData.pool).asset();

                DataTypes.LoanLiquidationData
                    memory liquidationData = loanCenter.getLoanLiquidationData(
                        params.loanId
                    );

                // Give max bid back to liquidator
                IERC20Upgradeable(asset).safeTransfer(
                    liquidationData.liquidator,
                    liquidationData.auctionMaxBid
                );
                // Get the fee from the user and give it to the auctioneer
                IERC20Upgradeable(asset).safeTransferFrom(
                    params.caller,
                    liquidationData.auctioneer,
                    loanCenter.getLoanAuctioneerFee(params.loanId)
                );
            }

            // Return the principal + interest
            ILendingPool(loanData.pool).receiveUnderlying(
                params.caller,
                loanData.amount,
                uint256(loanData.borrowRate),
                interest
            );

            // Repay the loan through the loan center contract
            loanCenter.repayLoan(params.loanId);

            // If a genesis NFT was used with this loan we need to unlock it
            if (loanData.genesisNFTId != 0) {
                // Unlock Genesis NFT
                IGenesisNFT(addressProvider.getGenesisNFT()).setLockedState(
                    uint256(loanData.genesisNFTId),
                    false
                );
            }

            // Transfer the collateral back to the owner
            for (uint256 i = 0; i < loanData.nftTokenIds.length; i++) {
                IERC721Upgradeable(loanData.nftAsset).safeTransferFrom(
                    address(loanCenter),
                    loanData.owner,
                    loanData.nftTokenIds[i]
                );
            }
        }
        // User is sending less than the total debt
        else {
            // User is sending less than interest or the interest entirely
            if (params.amount <= interest) {
                ILendingPool(loanData.pool).receiveUnderlying(
                    params.caller,
                    0,
                    uint256(loanData.borrowRate),
                    params.amount
                );

                // Calculate how much time the user has paid off with sent amount
                loanCenter.updateLoanDebtTimestamp(
                    params.loanId,
                    uint256(loanData.debtTimestamp) +
                        ((365 days *
                            params.amount *
                            PercentageMath.PERCENTAGE_FACTOR) /
                            (loanData.amount * uint256(loanData.borrowRate)))
                );
            }
            // User is sending the full interest and closing part of the loan
            else {
                ILendingPool(loanData.pool).receiveUnderlying(
                    params.caller,
                    params.amount - interest,
                    uint256(loanData.borrowRate),
                    interest
                );
                loanCenter.updateLoanDebtTimestamp(
                    params.loanId,
                    block.timestamp
                );
                loanCenter.updateLoanAmount(
                    params.loanId,
                    loanData.amount - params.amount + interest
                );
            }
        }
    }
}
