//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;

import {IPricingCurve} from "../../../interfaces/IPricingCurve.sol";
import {PercentageMath} from "../../../libraries/math/PercentageMath.sol";
import {ERC165} from "@openzeppelin/contracts/utils/introspection/ERC165.sol";

contract LinearPriceCurve is IPricingCurve, ERC165 {
    function priceAfterBuy(
        uint256 price,
        uint256 delta
    ) external pure override returns (uint256) {
        return price + delta;
    }

    function priceAfterSell(
        uint256 price,
        uint256 delta
    ) external pure override returns (uint256) {
        if (delta > price) {
            return 0;
        }
        return price - delta;
    }

    function validateDelta(uint256) external pure override returns (bool) {
        return true;
    }

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
