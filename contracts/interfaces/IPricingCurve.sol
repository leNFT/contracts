//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;

interface IPricingCurve {
    function priceAfterBuy(
        uint256 price,
        uint256 delta
    ) external pure returns (uint256);

    function priceAfterSell(
        uint256 price,
        uint256 delta
    ) external pure returns (uint256);

    function validateDelta(uint256 price) external view returns (bool);

    function validateSpotPrice(uint256 price) external view returns (bool);
}
