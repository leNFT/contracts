// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.8.15;

import {DataTypes} from "../types/DataTypes.sol";
import {ValidationLogic} from "./ValidationLogic.sol";
import {IMarketAddressesProvider} from "../../interfaces/IMarketAddressesProvider.sol";
import {ILoanCenter} from "../../interfaces/ILoanCenter.sol";
import {IReserve} from "../../interfaces/IReserve.sol";
import {IDebtToken} from "../../interfaces/IDebtToken.sol";
import {IERC721Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC721/IERC721Upgradeable.sol";
import {IERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";

library BorrowLogic {
    function borrow(
        IMarketAddressesProvider addressesProvider,
        mapping(address => address) storage reserves,
        address borrower,
        address asset,
        uint256 amount,
        address nftAddress,
        uint256 nftTokenID
    ) external returns (uint256) {
        // Get the reserve providing the loan
        address reserveAddress = reserves[asset];

        // Validate the movement
        ValidationLogic.validateBorrow(addressesProvider, amount, nftAddress);

        // Transfer the collateral
        IERC721Upgradeable(nftAddress).safeTransferFrom(
            borrower,
            addressesProvider.getLoanCenter(),
            nftTokenID
        );

        // Get the borrow rate index and create the loan
        uint256 borrowRate = IReserve(reserveAddress).getBorrowRate();

        ILoanCenter loanCenter = ILoanCenter(addressesProvider.getLoanCenter());
        uint256 loanId = loanCenter.createLoan(
            borrower,
            asset,
            amount,
            nftAddress,
            nftTokenID,
            borrowRate
        );

        // Mint the token representing the debt
        IDebtToken(addressesProvider.getDebtToken()).mint(borrower, loanId);

        //Activate Loan after the principal has been sent
        loanCenter.activateLoan(loanId);

        // Send the principal to the borrower
        IReserve(reserveAddress).transferUnderlying(
            borrower,
            amount,
            borrowRate
        );

        return loanId;
    }

    function repay(
        IMarketAddressesProvider addressesProvider,
        mapping(address => address) storage reserves,
        uint256 loanId,
        address caller
    ) external {
        // Validate the movement
        ValidationLogic.validateRepay(addressesProvider, loanId, caller);

        // Get the loan
        DataTypes.LoanData memory loanData = (
            ILoanCenter(addressesProvider.getLoanCenter())
        ).getLoan(loanId);

        // Return the principal + interest
        IReserve(reserves[loanData.reserveAsset]).receiveUnderlying(
            loanData.borrower,
            loanData.amount,
            loanData.borrowRate,
            ILoanCenter(addressesProvider.getLoanCenter()).getLoanInterest(
                loanId
            )
        );

        ILoanCenter(addressesProvider.getLoanCenter()).repayLoan(loanId);

        // Transfer the collateral back to the owner
        IERC721Upgradeable(loanData.nftAsset).safeTransferFrom(
            addressesProvider.getLoanCenter(),
            loanData.borrower,
            loanData.nftTokenId
        );

        // Burn the token representing the debt
        IDebtToken(addressesProvider.getDebtToken()).burn(loanId);
    }
}
