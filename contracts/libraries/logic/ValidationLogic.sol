// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.8.15;

import {DataTypes} from "../types/DataTypes.sol";
import {PercentageMath} from "../math/PercentageMath.sol";
import {INFTOracle} from "../../interfaces/INFTOracle.sol";
import {IInterestRate} from "../../interfaces/IInterestRate.sol";
import {IMarketAddressesProvider} from "../../interfaces/IMarketAddressesProvider.sol";
import {ILoanCenter} from "../../interfaces/ILoanCenter.sol";
import {IReserve} from "../../interfaces/IReserve.sol";
import {LoanLogic} from "./LoanLogic.sol";
import {IERC721Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC721/IERC721Upgradeable.sol";
import {IERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "hardhat/console.sol";

library ValidationLogic {
    using LoanLogic for DataTypes.LoanData;

    function validateWithdrawal(
        IMarketAddressesProvider addressesProvider,
        address reserveAddress,
        uint256 amount
    ) external view {
        // Check if the utilization rate doesn't go above maximum
        IReserve reserve = IReserve(reserveAddress);

        uint256 maximumUtilizationRate = reserve.getMaximumUtilizationRate();
        uint256 debt = reserve.getDebt();
        uint256 underlyingBalance = reserve.getUnderlyingBalance();
        uint256 updatedUtilizationRate = IInterestRate(
            addressesProvider.getInterestRate()
        ).calculateUtilizationRate(underlyingBalance - amount, debt);

        require(
            updatedUtilizationRate <= maximumUtilizationRate,
            "Reserve utilization rate too high"
        );

        // Check if the user has enough reserve balance for withdrawal
        require(
            amount <= reserve.getMaximumWithdrawalAmount(msg.sender),
            "Amount too high"
        );
    }

    // Check if borrowing conditions are valid
    function validateBorrow(
        IMarketAddressesProvider addressesProvider,
        address reserveAdress,
        uint256 amount,
        address nftAddress,
        uint256 nftTokenID
    ) external {
        INFTOracle nftOracle = INFTOracle(addressesProvider.getNFTOracle());

        // Check if nft collection is supported
        require(
            nftOracle.isNftSupported(nftAddress),
            "NFT COllection is not supported"
        );

        // Check if borrow amount exceeds allowed amount
        require(
            amount <= nftOracle.getCollectionMaxCollateralization(nftAddress),
            "Amount exceeds allowed by collateral"
        );

        // Check if the reserve has enough underlying to borrow
        require(
            amount <= IReserve(reserveAdress).getUnderlyingBalance(),
            "Amount exceeds reserve balance"
        );

        // Check if the borrower owns the asset
        require(
            IERC721Upgradeable(nftAddress).ownerOf(nftTokenID) == msg.sender,
            "Asset not owned by user"
        );
    }

    function validateRepay(
        IMarketAddressesProvider addressesProvider,
        uint256 loanId
    ) external view {
        ILoanCenter loanCenter = ILoanCenter(addressesProvider.getLoanCenter());
        //Require that loan exists
        DataTypes.LoanData memory loanData = loanCenter.getLoan(loanId);
        require(
            loanData.state != DataTypes.LoanState.None,
            "Loan does not exist"
        );

        // Check if caller trying to pay loan is borrower
        require(msg.sender == loanData.borrower, "Caller is not loan borrower");

        // Check the user has enough balance to repay
        uint256 balance = IERC20Upgradeable(
            IReserve(loanData.reserve).getAsset()
        ).balanceOf(msg.sender);
        require(
            balance >= loanCenter.getLoanDebt(loanId),
            "Balance is lower than loan debt"
        );
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

        // Check if caller has enough balance
        uint256 balance = IERC20Upgradeable(
            IReserve(loanData.reserve).getAsset()
        ).balanceOf(msg.sender);
        uint256 liquidationPrice = PercentageMath.percentMul(
            INFTOracle(addressesProvider.getNFTOracle()).getNftFloorPrice(
                loanData.nftAsset
            ),
            PercentageMath.ONE_HUNDRED_PERCENT -
                IReserve(loanData.reserve).getLiquidationPenalty() +
                IReserve(loanData.reserve).getProtocolLiquidationFee()
        );

        require(
            balance >= liquidationPrice,
            "Balance lower than liquidation price"
        );
    }
}
