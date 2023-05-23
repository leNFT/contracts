//SPDX-License-Identifier: Unlicense
pragma solidity 0.8.19;

import {IPricingCurve} from "../../../interfaces/IPricingCurve.sol";
import {PercentageMath} from "../../../libraries/utils/PercentageMath.sol";
import {ERC165} from "@openzeppelin/contracts/utils/introspection/ERC165.sol";

/// @title Exponential Price Curve Contract
/// @notice This contract implements an exponential price curve
contract ExponentialPriceCurve is IPricingCurve, ERC165 {
    /// @notice Calculates the price after buying 1 token
    /// @param price The current price of the token
    /// @param delta The delta factor to increase the price
    /// @return The updated price after buying
    function priceAfterBuy(
        uint256 price,
        uint256 delta,
        uint256
    ) external pure override returns (uint256) {
        return
            PercentageMath.percentMul(
                price,
                PercentageMath.PERCENTAGE_FACTOR + delta
            );
    }

    /// @notice Calculates the price after selling 1 token
    /// @param price The current price of the token
    /// @param delta The delta factor to decrease the price
    /// @return The updated price after selling
    function priceAfterSell(
        uint256 price,
        uint256 delta,
        uint256
    ) external pure override returns (uint256) {
        return
            PercentageMath.percentDiv(
                price,
                PercentageMath.PERCENTAGE_FACTOR + delta
            );
    }

    /// @notice Validates the parameters for a liquidity provider deposit
    /// @param spotPrice The initial spot price of the LP
    /// @param delta The delta of the LP
    /// @param fee The fee of the LP
    function validateLpParameters(
        uint256 spotPrice,
        uint256 delta,
        uint256 fee
    ) external pure override {
        require(spotPrice > 0, "EPC:VLPP:INVALID_PRICE");
        require(
            delta < PercentageMath.PERCENTAGE_FACTOR,
            "EPC:VLPP:INVALID_DELTA"
        );
        if (fee > 0 && delta > 0) {
            // If this doesn't happen then a user would be able to profitably buy and sell from the same LP and drain its funds
            require(
                PercentageMath.PERCENTAGE_FACTOR *
                    (PercentageMath.PERCENTAGE_FACTOR + fee) >
                    (PercentageMath.PERCENTAGE_FACTOR + delta) *
                        (PercentageMath.PERCENTAGE_FACTOR - fee),
                "EPC:VLPP:INVALID_FEE_DELTA_RATIO"
            );
        }
    }

    function supportsInterface(
        bytes4 interfaceId
    ) public view override returns (bool) {
        return
            interfaceId == type(IPricingCurve).interfaceId ||
            super.supportsInterface(interfaceId);
    }
}
