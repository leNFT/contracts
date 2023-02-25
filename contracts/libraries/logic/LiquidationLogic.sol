// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.8.17;

import {DataTypes} from "../types/DataTypes.sol";
import {PercentageMath} from "../math/PercentageMath.sol";
import {ValidationLogic} from "./ValidationLogic.sol";
import {IAddressesProvider} from "../../interfaces/IAddressesProvider.sol";
import {IFeeDistributor} from "../../interfaces/IFeeDistributor.sol";
import {ILoanCenter} from "../../interfaces/ILoanCenter.sol";
import {ILendingPool} from "../../interfaces/ILendingPool.sol";
import {IDebtToken} from "../../interfaces/IDebtToken.sol";
import {INFTOracle} from "../../interfaces/INFTOracle.sol";
import {IGenesisNFT} from "../../interfaces/IGenesisNFT.sol";
import {ITokenOracle} from "../../interfaces/ITokenOracle.sol";
import {IERC721Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC721/IERC721Upgradeable.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {IERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import {SafeERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import {Trustus} from "../../protocol/Trustus/Trustus.sol";
import "hardhat/console.sol";

/// @title LiquidationLogic
/// @notice Contains the logic for the liquidate function
library LiquidationLogic {
    using SafeERC20Upgradeable for IERC20Upgradeable;

    /// @notice Liquidates a loan
    /// @param addressesProvider The address of the addresses provider
    /// @param params A struct with the parameters of the liquidate function
    function liquidate(
        IAddressesProvider addressesProvider,
        DataTypes.LiquidationParams memory params
    ) external {
        // Verify if liquidation conditions are met
        ValidationLogic.validateLiquidation(addressesProvider, params);

        // Get the loan
        DataTypes.LoanData memory loanData = (
            ILoanCenter(addressesProvider.getLoanCenter())
        ).getLoan(params.loanId);

        // Get the address of this asset's reserve
        address poolAsset = IERC4626(loanData.pool).asset();

        // Find the liquidation price
        uint256 liquidationPrice = ILoanCenter(
            addressesProvider.getLoanCenter()
        ).getLoanLiquidationPrice(params.loanId, params.request, params.packet);

        console.log("liquidationPrice", liquidationPrice);

        // Get the payment from the liquidator
        IERC20Upgradeable(poolAsset).safeTransferFrom(
            params.caller,
            address(this),
            liquidationPrice
        );

        // Repay loan...
        uint256 fundsLeft = liquidationPrice;
        uint256 loanInterest = ILoanCenter(addressesProvider.getLoanCenter())
            .getLoanInterest(params.loanId);
        uint256 loanDebt = loanData.amount + loanInterest;
        // If we only have funds to pay back part of the loan
        if (fundsLeft < loanDebt) {
            ILendingPool(loanData.pool).receiveUnderlyingDefaulted(
                address(this),
                fundsLeft,
                loanData.borrowRate,
                loanData.amount
            );
            console.log("receiveUnderlyingDefaulted", fundsLeft);
            fundsLeft = 0;
            // If we have funds to cover the whole debt associated with the loan
        } else {
            ILendingPool(loanData.pool).receiveUnderlying(
                address(this),
                loanData.amount,
                loanData.borrowRate,
                loanInterest
            );
            console.log("receiveUnderlying", loanDebt);
            fundsLeft -= loanDebt;
        }

        // ... then get the protocol liquidation fee (if there are still funds available) ...
        if (fundsLeft > 0) {
            uint256 protocolFee = PercentageMath.percentMul(
                liquidationPrice,
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
                loanData.borrower,
                fundsLeft
            );
        }

        // Update the state of the loan
        ILoanCenter(addressesProvider.getLoanCenter()).liquidateLoan(
            params.loanId
        );

        // Send collateral to liquidator
        for (uint i = 0; i < loanData.nftTokenIds.length; i++) {
            IERC721Upgradeable(loanData.nftAsset).safeTransferFrom(
                addressesProvider.getLoanCenter(),
                params.caller,
                loanData.nftTokenIds[i]
            );
        }

        // Unlock Genesis NFT
        if (loanData.genesisNFTId != 0) {
            IGenesisNFT(addressesProvider.getGenesisNFT()).setActiveState(
                loanData.genesisNFTId,
                false
            );
        }

        // Burn the token representing the debt
        IDebtToken(addressesProvider.getDebtToken()).burn(params.loanId);
    }
}
