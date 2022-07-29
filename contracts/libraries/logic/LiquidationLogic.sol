// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.8.15;

import {DataTypes} from "../types/DataTypes.sol";
import {PercentageMath} from "../math/PercentageMath.sol";
import {ValidationLogic} from "./ValidationLogic.sol";
import {IAddressesProvider} from "../../interfaces/IAddressesProvider.sol";
import {ILoanCenter} from "../../interfaces/ILoanCenter.sol";
import {IReserve} from "../../interfaces/IReserve.sol";
import {IDebtToken} from "../../interfaces/IDebtToken.sol";
import {INFTOracle} from "../../interfaces/INFTOracle.sol";
import {ITokenOracle} from "../../interfaces/ITokenOracle.sol";
import {IERC721Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC721/IERC721Upgradeable.sol";
import {IERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import {SafeERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import {Trustus} from "../../protocol/Trustus.sol";
import "hardhat/console.sol";

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
                PercentageMath.PERCENTAGE_FACTOR -
                    IReserve(reserveAddress).getLiquidationPenalty() +
                    IReserve(reserveAddress).getLiquidationFee()
            );
    }

    function liquidate(
        IAddressesProvider addressesProvider,
        uint256 loanId,
        bytes32 request,
        Trustus.TrustusPacket calldata packet
    ) external {
        // Verify if liquidation conditions are met
        ValidationLogic.validateLiquidation(
            addressesProvider,
            loanId,
            request,
            packet
        );

        // Get the loan
        DataTypes.LoanData memory loanData = (
            ILoanCenter(addressesProvider.getLoanCenter())
        ).getLoan(loanId);

        address reserveAsset = IReserve(loanData.reserve).getAsset();

        console.log("reserveAsset", reserveAsset);

        // Find the liquidation price
        ITokenOracle tokenOracle = ITokenOracle(
            addressesProvider.getTokenOracle()
        );
        uint256 baseTokenETHPrice = tokenOracle.getTokenETHPrice(reserveAsset);
        uint256 pricePrecision = tokenOracle.getPricePrecision();

        uint256 tokenPrice = (
            (INFTOracle(addressesProvider.getNFTOracle()).getTokenETHPrice(
                loanData.nftAsset,
                loanData.nftTokenId,
                request,
                packet
            ) * baseTokenETHPrice)
        ) / pricePrecision;
        uint256 liquidationPrice = _getLiquidationPrice(
            loanData.reserve,
            tokenPrice
        );
        console.log("liquidationPrice", liquidationPrice);
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
            console.log("receiveUnderlyingDefaulted", fundsLeft);
            fundsLeft = 0;
            // If we have funds to cover the whole debt associated with the loan
        } else {
            IReserve(loanData.reserve).receiveUnderlying(
                address(this),
                loanData.amount,
                loanData.borrowRate,
                loanInterest
            );
            console.log("receiveUnderlying", repayLoanAmount);
            fundsLeft -= repayLoanAmount;
        }

        // ... then get the protocol liquidation fee (if there are still funds available) ...
        if (fundsLeft > 0) {
            uint256 protocolFee = PercentageMath.percentMul(
                tokenPrice,
                IReserve(loanData.reserve).getLiquidationFee()
            );
            if (protocolFee > fundsLeft) {
                protocolFee = fundsLeft;
            }
            IERC20Upgradeable(reserveAsset).safeTransfer(
                addressesProvider.getFeeTreasury(),
                protocolFee
            );
            fundsLeft -= protocolFee;
        }

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
