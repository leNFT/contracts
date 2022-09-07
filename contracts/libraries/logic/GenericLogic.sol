// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.8.15;

import {DataTypes} from "../types/DataTypes.sol";
import {IReserve} from "../../interfaces/IReserve.sol";
import {IAddressesProvider} from "../../interfaces/IAddressesProvider.sol";
import {ILoanCenter} from "../../interfaces/ILoanCenter.sol";
import {INFTOracle} from "../../interfaces/INFTOracle.sol";
import {ITokenOracle} from "../../interfaces/ITokenOracle.sol";
import {INativeTokenVault} from "../../interfaces/INativeTokenVault.sol";
import {PercentageMath} from "../math/PercentageMath.sol";
import {LoanLogic} from "./LoanLogic.sol";
import {Trustus} from "../../protocol/Trustus.sol";

library GenericLogic {
    // Return the liquidation price in the borrowed asset and the token rewards
    function getLoanLiquidationPrice(
        IAddressesProvider addressesProvider,
        uint256 loanId,
        bytes32 request,
        Trustus.TrustusPacket calldata packet
    ) external view returns (uint256, uint256) {
        // Get the loan and its debt
        DataTypes.LoanData memory loanData = (
            ILoanCenter(addressesProvider.getLoanCenter())
        ).getLoan(loanId);
        uint256 loanDebt = (ILoanCenter(addressesProvider.getLoanCenter()))
            .getLoanDebt(loanId);

        // Get the address of this asset's reserve
        address reserveAsset = IReserve(loanData.reserve).getAsset();

        // Get the price of the collateral asset in the reserve asset. Ex: Punk #42 = 5 USDC
        ITokenOracle tokenOracle = ITokenOracle(
            addressesProvider.getTokenOracle()
        );
        uint256 reserveAssetETHPrice = tokenOracle.getTokenETHPrice(
            reserveAsset
        );
        uint256 pricePrecision = tokenOracle.getPricePrecision();
        uint256 tokenPrice = (
            (INFTOracle(addressesProvider.getNFTOracle()).getTokenETHPrice(
                loanData.nftAsset,
                loanData.nftTokenId,
                request,
                packet
            ) * pricePrecision)
        ) / reserveAssetETHPrice;

        // Threshold at which liquidation price starts being equal to debt
        uint256 liquidationThreshold = PercentageMath.percentMul(
            tokenPrice,
            PercentageMath.PERCENTAGE_FACTOR -
                IReserve(loanData.reserve).getLiquidationPenalty() +
                IReserve(loanData.reserve).getLiquidationFee()
        );

        // Find the cost of liquidation
        uint256 liquidationPrice;
        if (loanDebt < liquidationThreshold) {
            liquidationPrice = liquidationThreshold;
        } else {
            liquidationPrice = loanDebt;
        }

        // Find the liquidation reward
        uint256 liquidationReward = INativeTokenVault(
            addressesProvider.getNativeTokenVault()
        ).getLiquidationReward(
                reserveAssetETHPrice,
                tokenPrice,
                liquidationPrice
            );

        return (liquidationPrice, liquidationReward);
    }
}
