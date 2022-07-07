// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.8.15;

import {DataTypes} from "../types/DataTypes.sol";
import {INFTOracle} from "../../interfaces/INFTOracle.sol";
import {IInterestRate} from "../../interfaces/IInterestRate.sol";
import {IMarketAddressesProvider} from "../../interfaces/IMarketAddressesProvider.sol";
import {ILoanCenter} from "../../interfaces/ILoanCenter.sol";
import {IReserve} from "../../interfaces/IReserve.sol";
import {LoanLogic} from "./LoanLogic.sol";
import "hardhat/console.sol";

library ValidationLogic {
    using LoanLogic for DataTypes.LoanData;

    function validateWithdrawal(
        IMarketAddressesProvider addressesProvider,
        address reserveAddress,
        uint256 amount
    ) external view {
        // Check if the utilization rate doesn't go above maximum
        uint256 maximumUtilizationRate = IReserve(reserveAddress)
            .getMaximumUtilizationRate();
        uint256 debt = IReserve(reserveAddress).getDebt();
        uint256 underlyingBalance = IReserve(reserveAddress)
            .getUnderlyingBalance();
        uint256 updatedUtilizationRate = IInterestRate(
            addressesProvider.getInterestRate()
        ).calculateUtilizationRate(underlyingBalance - amount, debt);

        console.log("updatedUtilizationRate", updatedUtilizationRate);
        console.log("maximumUtilizationRate", maximumUtilizationRate);
        console.log("underlyingBalance", underlyingBalance);
        console.log("amount", amount);
        console.log("debt", debt);

        require(
            updatedUtilizationRate < maximumUtilizationRate,
            "Withdrawal makes reserve go above maximum utilization rate"
        );
    }

    // Check if borrowing conditions are valid
    function validateBorrow(
        IMarketAddressesProvider addressesProvider,
        uint256 amount,
        address nftAddress
    ) external {
        INFTOracle nftOracle = INFTOracle(addressesProvider.getNFTOracle());

        // Check if nft collection is supported
        require(
            nftOracle.isNftSupported(nftAddress),
            "NFT COllection is not supported"
        );

        uint256 maxCollaterization = nftOracle
            .getCollectionMaxCollateralization(nftAddress);

        // Check if borrow amount exceeds allowed amount
        require(
            amount < maxCollaterization,
            "Amount exceeds allowed by collateral"
        );
    }

    function validateRepay(
        IMarketAddressesProvider addressesProvider,
        uint256 loanId,
        address caller
    ) external view {
        //Require that loan exists
        DataTypes.LoanData memory loanData = ILoanCenter(
            addressesProvider.getLoanCenter()
        ).getLoan(loanId);
        require(
            loanData.state != DataTypes.LoanState.None,
            "Loan does not exist"
        );

        // Check if caller trying to pay loan is borrower
        require(caller == loanData.borrower, "Caller is not loan borrower");
    }

    function validateLiquidation(
        IMarketAddressesProvider addressesProvider,
        uint256 loanId
    ) external view {
        //Require that loan exists
        DataTypes.LoanData memory loanData = ILoanCenter(
            addressesProvider.getLoanCenter()
        ).getLoan(loanId);
        require(
            loanData.state != DataTypes.LoanState.None,
            "Loan does not exist"
        );

        // Check if collateral / debt relation allows for liquidation
        require(
            INFTOracle(addressesProvider.getNFTOracle())
                .getCollectionMaxCollateralization(loanData.nftAsset) <
                ILoanCenter(addressesProvider.getLoanCenter()).getLoanDebt(
                    loanId
                ),
            "Collateral / Debt loan relation does not allow for liquidation."
        );
    }
}
