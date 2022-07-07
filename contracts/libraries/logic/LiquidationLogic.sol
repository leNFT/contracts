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

    function _getLiquidationPrice(address reserveAddress, uint256 floorPrice)
        internal
        view
        returns (uint256)
    {
        return
            PercentageMath.percentMul(
                floorPrice,
                PercentageMath.ONE_HUNDRED_PERCENT -
                    IReserve(reserveAddress).getLiquidationPenalty() +
                    IReserve(reserveAddress).getProtocolLiquidationFee()
            );
    }

    function liquidate(
        IMarketAddressesProvider addressesProvider,
        uint256 loanId
    ) external {
        // Verify if liquidation conditions are met
        ValidationLogic.validateLiquidation(addressesProvider, loanId);

        // Get the loan
        DataTypes.LoanData memory loanData = (
            ILoanCenter(addressesProvider.getLoanCenter())
        ).getLoan(loanId);

        address reserveAsset = IReserve(loanData.reserve).getAsset();

        // Find the liquidation price
        uint256 floorPrice = INFTOracle(addressesProvider.getNFTOracle())
            .getNftFloorPrice(loanData.nftAsset);
        uint256 liquidationPrice = _getLiquidationPrice(
            loanData.reserve,
            floorPrice
        );
        // Send the payment from the liquidator
        IERC20Upgradeable(reserveAsset).safeTransferFrom(
            msg.sender,
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
            IReserve(loanData.reserve).receiveUnderlyingDefaulted(
                address(this),
                fundsLeft,
                loanData.borrowRate,
                loanData.amount
            );
            fundsLeft = 0;
            // If we have funds to cover the whole debt associated with the loan
        } else {
            IReserve(loanData.reserve).receiveUnderlying(
                address(this),
                loanData.amount,
                loanData.borrowRate,
                loanInterest
            );
            fundsLeft -= repayLoanAmount;
        }

        // ... then get the protocol liquidation fee (if there are still funds available) ...

        uint256 protocolFee = floorPrice *
            IReserve(loanData.reserve).getProtocolLiquidationFee();
        if (protocolFee < fundsLeft) {
            protocolFee = fundsLeft;
        }
        IERC20Upgradeable(reserveAsset).safeTransfer(
            addressesProvider.getFeeTreasury(),
            protocolFee
        );
        fundsLeft -= protocolFee;

        // ... and the rest to the borrower.
        if (fundsLeft > 0) {
            IERC20Upgradeable(reserveAsset).safeTransfer(
                loanData.borrower,
                fundsLeft
            );
        }

        // Update the state of the loan
        ILoanCenter(addressesProvider.getLoanCenter()).liquidateLoan(loanId);

        // Send collateral to liquidator
        IERC721Upgradeable(loanData.nftAsset).safeTransferFrom(
            addressesProvider.getLoanCenter(),
            msg.sender,
            loanData.nftTokenId
        );

        // Burn the token representing the debt
        IDebtToken(addressesProvider.getDebtToken()).burn(loanId);
    }
}
