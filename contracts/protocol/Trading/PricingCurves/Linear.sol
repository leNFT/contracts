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
        uint256 fee
    ) external pure override returns (uint256) {
        // If the next price makes it so the next sell price is higher than the current buy price we dont update
        uint256 nextSellPrice = ((price + delta) *
            (PercentageMath.PERCENTAGE_FACTOR - fee)) /
            PercentageMath.PERCENTAGE_FACTOR;
        uint256 currentBuyPrice = (price *
            (PercentageMath.PERCENTAGE_FACTOR + fee)) /
            PercentageMath.PERCENTAGE_FACTOR;

        if (nextSellPrice < currentBuyPrice) {
            return price + delta;
        }
        return price;
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
        if (delta > price) {
            return price;
        }

        // If the next price makes it so the next buy price is lower than the current sell price we dont update
        uint256 nextBuyPrice = ((price - delta) *
            (PercentageMath.PERCENTAGE_FACTOR + fee)) /
            PercentageMath.PERCENTAGE_FACTOR;
        uint256 currentSellPrice = (price *
            (PercentageMath.PERCENTAGE_FACTOR - fee)) /
            PercentageMath.PERCENTAGE_FACTOR;

        if (nextBuyPrice > currentSellPrice) {
            return price - delta;
        }

        return price;
    }

    function validateLpParameters(
        uint256 spotPrice,
        uint256,
        uint256
    ) external pure override {
        require(spotPrice > 0, "LPC:VLPP:INVALID_PRICE");
    }

    function supportsInterface(
        bytes4 interfaceId
    ) public view override returns (bool) {
        return
            interfaceId == type(IPricingCurve).interfaceId ||
            super.supportsInterface(interfaceId);
    }
}
