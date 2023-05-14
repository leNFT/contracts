//SPDX-License-Identifier: Unlicense
pragma solidity 0.8.19;

import {IPricingCurve} from "../../../interfaces/IPricingCurve.sol";
import {ERC165} from "@openzeppelin/contracts/utils/introspection/ERC165.sol";
import {PercentageMath} from "../../../libraries/utils/PercentageMath.sol";

contract LinearPriceCurve is IPricingCurve, ERC165 {
    /// @notice Calculates the price after buying 1 token
    /// @param price The current price of the token
    /// @param delta The delta factor to increase the price
    /// @return The updated price after buying
    function priceAfterBuy(
        uint256 price,
        uint256 delta,
        uint256
    ) external pure override returns (uint256) {
        return price + delta;
    }

    /// @notice Calculates the price after selling 1 token
    /// @param price The current price of the token
    /// @param delta The delta factor to decrease the price
    /// @return The updated price after selling
    function priceAfterSell(
        uint256 price,
        uint256 delta,
        uint256 fee
    ) external pure override returns (uint256) {
        // If the next price makes it so the next buy price is lower than the current sell price we dont update
        if (
            ((price - delta) * (PercentageMath.PERCENTAGE_FACTOR + fee)) >
            (price * (PercentageMath.PERCENTAGE_FACTOR - fee))
        ) {
            return price - delta;
        }

        return price;
    }

    function validateLpParameters(
        uint256 spotPrice,
        uint256 delta,
        uint256 fee
    ) external pure override {
        require(spotPrice > 0, "LPC:VLPP:INVALID_PRICE");

        if (fee > 0 && delta > 0) {
            // If this doesn't happen then a user would be able to profitably buy and sell from the same LP and drain its funds
            require(
                ((spotPrice - delta) *
                    (PercentageMath.PERCENTAGE_FACTOR + fee)) >
                    (spotPrice * (PercentageMath.PERCENTAGE_FACTOR - fee)),
                "LPC:VLPP:INVALID_FEE_DELTA_RATIO"
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
