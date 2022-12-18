//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;

import {IPricingCurve} from "../../interfaces/IPricingCurve.sol";
import {PercentageMath} from "../../libraries/math/PercentageMath.sol";

contract ExponentialPriceCurve is IPricingCurve {
    function priceAfterBuy(
        uint256 price,
        uint256 delta
    ) external pure override returns (uint256) {
        return
            ((PercentageMath.PERCENTAGE_FACTOR + delta) * price) /
            PercentageMath.PERCENTAGE_FACTOR;
    }

    function priceAfterSell(
        uint256 price,
        uint256 delta
    ) external pure override returns (uint256) {
        return
            ((PercentageMath.PERCENTAGE_FACTOR - delta) * price) /
            PercentageMath.PERCENTAGE_FACTOR;
    }
}
