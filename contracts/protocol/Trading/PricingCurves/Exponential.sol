//SPDX-License-Identifier: Unlicense
pragma solidity 0.8.19;

import {IPricingCurve} from "../../../interfaces/IPricingCurve.sol";
import {PercentageMath} from "../../../libraries/math/PercentageMath.sol";
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
        uint256 delta
    ) external pure override returns (uint256) {
        return
            ((PercentageMath.PERCENTAGE_FACTOR + delta) * price) /
            PercentageMath.PERCENTAGE_FACTOR;
    }

    /// @notice Calculates the price after selling 1 token
    /// @param price The current price of the token
    /// @param delta The delta factor to decrease the price
    /// @return The updated price after selling
    function priceAfterSell(
        uint256 price,
        uint256 delta
    ) external pure override returns (uint256) {
        return
            ((PercentageMath.PERCENTAGE_FACTOR - delta) * price) /
            PercentageMath.PERCENTAGE_FACTOR;
    }

    /// @notice Validates delta factor
    /// @param delta The delta factor to validate
    /// @return A boolean indicating if the delta factor is valid or not
    function validateDelta(
        uint256 delta
    ) external pure override returns (bool) {
        if (delta < PercentageMath.PERCENTAGE_FACTOR) {
            return true;
        }
        return false;
    }

    /// @notice Validates the spot price
    /// @return A boolean indicating if the spot price is valid or not
    function validateSpotPrice(uint256) external pure override returns (bool) {
        return true;
    }

    function supportsInterface(
        bytes4 interfaceId
    ) public view override returns (bool) {
        return
            interfaceId == type(IPricingCurve).interfaceId ||
            super.supportsInterface(interfaceId);
    }
}
