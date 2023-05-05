// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.8.19;

import {DataTypes} from "../types/DataTypes.sol";
import {PercentageMath} from "../math/PercentageMath.sol";
import {ValidationLogic} from "./ValidationLogic.sol";
import {IAddressesProvider} from "../../interfaces/IAddressesProvider.sol";
import {ILoanCenter} from "../../interfaces/ILoanCenter.sol";
import {ILendingPool} from "../../interfaces/ILendingPool.sol";
import {IDebtToken} from "../../interfaces/IDebtToken.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {IGenesisNFT} from "../../interfaces/IGenesisNFT.sol";
import {IERC721Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC721/IERC721Upgradeable.sol";
import {IERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import {SafeERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";

/// @title BorrowLogic
/// @notice Contains the logic for the borrow and repay functions
library BorrowLogic {
    using SafeERC20Upgradeable for IERC20Upgradeable;

    /// @notice Creates a new loan, transfers the collateral to the loan center and mints the debt token
    /// @param addressesProvider The address of the addresses provider
    /// @param lendingPool The address of the lending pool
    /// @param params A struct with the parameters of the borrow function
    /// @return loanId The id of the new loan
    function borrow(
        IAddressesProvider addressesProvider,
        address lendingPool,
        DataTypes.BorrowParams memory params
    ) external returns (uint256 loanId) {
        // Validate the movement
        ValidationLogic.validateBorrow(addressesProvider, lendingPool, params);

        // Get the loan center
        ILoanCenter loanCenter = ILoanCenter(addressesProvider.getLoanCenter());

        // Transfer the collateral to the loan center
        for (uint256 i = 0; i < params.nftTokenIds.length; i++) {
            IERC721Upgradeable(params.nftAddress).safeTransferFrom(
                params.caller,
                address(loanCenter),
                params.nftTokenIds[i]
            );
        }

        // Get the borrow rate index
        uint256 borrowRate = ILendingPool(lendingPool).getBorrowRate();

        // Get max LTV for this collection
        uint256 maxLTV = loanCenter.getCollectionMaxCollaterization(
            params.nftAddress
        );

        // Get boost for this user and collection
        uint256 boost;
        // If a genesis NFT was used with this loan
        if (params.genesisNFTId != 0) {
            IGenesisNFT genesisNFT = IGenesisNFT(
                addressesProvider.getGenesisNFT()
            );

            boost = genesisNFT.getLTVBoost();

            // Lock genesis NFT to this loan
            genesisNFT.setLockedState(params.genesisNFTId, true);
        }

        // Create the loan
        loanId = loanCenter.createLoan(
            lendingPool,
            params.amount,
            maxLTV,
            boost,
            params.genesisNFTId,
            params.nftAddress,
            params.nftTokenIds,
            borrowRate
        );

        // Mint the token representing the debt
        IDebtToken(addressesProvider.getDebtToken()).mint(
            params.onBehalfOf,
            loanId
        );

        //Activate Loan
        loanCenter.activateLoan(loanId);

        // Send the principal to the borrower
        ILendingPool(lendingPool).transferUnderlying(
            params.caller,
            params.amount,
            borrowRate
        );
    }

    /// @notice Repays a loan, transfers the principal and interest to the lending pool and returns the collateral to the owner
    /// @param addressesProvider The address of the addresses provider
    /// @param params A struct with the parameters of the repay function
    function repay(
        IAddressesProvider addressesProvider,
        DataTypes.RepayParams memory params
    ) external {
        // Get the loan
        ILoanCenter loanCenter = ILoanCenter(addressesProvider.getLoanCenter());
        DataTypes.LoanData memory loanData = loanCenter.getLoan(params.loanId);
        uint256 loanDebt = loanCenter.getLoanDebt(params.loanId);

        // Validate the movement
        ValidationLogic.validateRepay(params, loanData.state, loanDebt);

        uint256 interest = loanCenter.getLoanInterest(params.loanId);

        // If we are paying the entire loan debt
        if (params.amount == loanCenter.getLoanDebt(params.loanId)) {
            // If the loan was being liquidated we send the liquidators payment back with a fee
            if (loanData.state == DataTypes.LoanState.Auctioned) {
                DataTypes.LoanLiquidationData
                    memory liquidationData = loanCenter.getLoanLiquidationData(
                        params.loanId
                    );
                // Get the payment from the liquidator
                IERC20Upgradeable(IERC4626(loanData.pool).asset())
                    .safeTransferFrom(
                        address(this),
                        liquidationData.liquidator,
                        liquidationData.auctionMaxBid
                    );
                // Get the fee from the user
                IERC20Upgradeable(IERC4626(loanData.pool).asset())
                    .safeTransferFrom(
                        params.caller,
                        liquidationData.auctioner,
                        (liquidationData.auctionMaxBid *
                            ILendingPool(loanData.pool)
                                .getPoolConfig()
                                .auctionerFee) /
                            PercentageMath.PERCENTAGE_FACTOR
                    );
            }

            // Return the principal + interest
            ILendingPool(loanData.pool).receiveUnderlying(
                params.caller,
                loanData.amount,
                loanData.borrowRate,
                interest
            );

            loanCenter.repayLoan(params.loanId);

            if (loanData.genesisNFTId != 0) {
                // Unlock Genesis NFT
                IGenesisNFT(addressesProvider.getGenesisNFT()).setLockedState(
                    loanData.genesisNFTId,
                    false
                );
            }

            // Transfer the collateral back to the owner
            for (uint256 i = 0; i < loanData.nftTokenIds.length; i++) {
                IERC721Upgradeable(loanData.nftAsset).safeTransferFrom(
                    address(loanCenter),
                    IERC721Upgradeable(addressesProvider.getDebtToken())
                        .ownerOf(params.loanId),
                    loanData.nftTokenIds[i]
                );
            }

            // Burn the token representing the debt
            IDebtToken(addressesProvider.getDebtToken()).burn(params.loanId);
        }
        // User is sending less than the total debt
        else {
            // User is sending less than the interest
            if (params.amount <= interest) {
                ILendingPool(loanData.pool).receiveUnderlying(
                    params.caller,
                    0,
                    loanData.borrowRate,
                    params.amount
                );

                // Calculate how much time the user has paid off with sent amount
                loanCenter.updateLoanDebtTimestamp(
                    params.loanId,
                    loanData.debtTimestamp +
                        ((365 days *
                            params.amount *
                            PercentageMath.PERCENTAGE_FACTOR) /
                            (loanData.amount * loanData.borrowRate))
                );
            }
            // User is sending the full interest and closing part of the loan
            else {
                ILendingPool(loanData.pool).receiveUnderlying(
                    params.caller,
                    params.amount - interest,
                    loanData.borrowRate,
                    interest
                );
                loanCenter.updateLoanDebtTimestamp(
                    params.loanId,
                    block.timestamp
                );
                loanCenter.updateLoanAmount(
                    params.loanId,
                    loanData.amount - (params.amount - interest)
                );
            }
        }
    }
}
