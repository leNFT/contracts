// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.8.15;

import {DataTypes} from "../types/DataTypes.sol";
import {INFTOracle} from "../../interfaces/INFTOracle.sol";
import {IMarketAddressesProvider} from "../../interfaces/IMarketAddressesProvider.sol";
import {ILoanCenter} from "../../interfaces/ILoanCenter.sol";
import {IReserve} from "../../interfaces/IReserve.sol";
import {LoanLogic} from "./LoanLogic.sol";

library ValidationLogic {
    using LoanLogic for DataTypes.LoanData;

    // Check if bnorrowing conditions are valid
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
