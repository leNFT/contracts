// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.8.15;

import {DataTypes} from "../types/DataTypes.sol";
import {PercentageMath} from "../math/PercentageMath.sol";
import {ValidationLogic} from "./ValidationLogic.sol";
import {IMarketAddressesProvider} from "../../interfaces/IMarketAddressesProvider.sol";
import {ILoanCenter} from "../../interfaces/ILoanCenter.sol";
import {IReserve} from "../../interfaces/IReserve.sol";
import {IDebtToken} from "../../interfaces/IDebtToken.sol";
import {INFTOracle} from "../../interfaces/INFTOracle.sol";
import {IERC721Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC721/IERC721Upgradeable.sol";
import {IERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import {SafeERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";

library LiquidationLogic {
    using SafeERC20Upgradeable for IERC20Upgradeable;

    function liquidate(
        IMarketAddressesProvider addressesProvider,
        mapping(address => address) storage reserves,
        uint256 loanId,
        address liquidator
    ) external {
        // Verify if liquidation conditions are met
        ValidationLogic.validateLiquidation(addressesProvider, loanId);

        // Get the loan
        DataTypes.LoanData memory loanData = (
            ILoanCenter(addressesProvider.getLoanCenter())
        ).getLoan(loanId);

        address reserveAddress = reserves[loanData.reserveAsset];

        // Find the liquidation price
        uint256 floorPrice = INFTOracle(addressesProvider.getNFTOracle())
            .getNftFloorPrice(loanData.nftAsset);
        uint256 liquidationPrice = PercentageMath.percentMul(
            floorPrice,
            PercentageMath.ONE_HUNDRED_PERCENT -
                IReserve(reserveAddress).getLiquidationPenalty() +
                IReserve(reserveAddress).getProtocolLiquidationFee()
        );

        // Send the payment from the liquidator
        IERC20Upgradeable(loanData.reserveAsset).safeTransferFrom(
            liquidator,
            address(this),
            liquidationPrice
        );

        // Repay loan...
        uint256 fundsLeft = liquidationPrice;
        uint256 loanInterest = ILoanCenter(addressesProvider.getLoanCenter())
            .getLoanInterest(loanId);
        uint256 repayLoanAmount = loanData.amount + loanInterest;
        // If we only have funds to pay back part of the loan
        if (fundsLeft < repayLoanAmount) {
            IReserve(reserveAddress).receiveUnderlyingDefaulted(
                address(this),
                fundsLeft,
                loanData.borrowRate,
                loanData.amount
            );
            fundsLeft = 0;
            // If we have funds to cover the whole debt associated with the loan
        } else {
            IReserve(reserveAddress).receiveUnderlying(
                address(this),
                loanData.amount,
                loanData.borrowRate,
                loanInterest
            );
            fundsLeft -= repayLoanAmount;
        }

        // ... then get the protocol liquidation fee (if there are still funds available) ...

        uint256 protocolFee = floorPrice *
            IReserve(reserveAddress).getProtocolLiquidationFee();
        if (protocolFee < fundsLeft) {
            protocolFee = fundsLeft;
        }
        IERC20Upgradeable(loanData.reserveAsset).safeTransfer(
            addressesProvider.getFeeTreasury(),
            protocolFee
        );
        fundsLeft -= protocolFee;

        // ... and the rest to the borrower.
        if (fundsLeft > 0) {
            IERC20Upgradeable(loanData.reserveAsset).safeTransfer(
                loanData.borrower,
                fundsLeft
            );
        }

        // Update the state of the loan
        ILoanCenter(addressesProvider.getLoanCenter()).liquidateLoan(loanId);

        // Send collateral to liquidator
        IERC721Upgradeable(loanData.nftAsset).safeTransferFrom(
            addressesProvider.getLoanCenter(),
            liquidator,
            loanData.nftTokenId
        );

        // Burn the token representing the debt
        IDebtToken(addressesProvider.getDebtToken()).burn(loanId);
    }
}
