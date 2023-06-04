//SPDX-License-Identifier: Unlicense
pragma solidity 0.8.19;

interface ISwapRouter {
    function approveTradingPool(address token, address tradingPool) external;

    function swap(
        address buyPool,
        address sellPool,
        uint256[] memory buyNftIds,
        uint256 maximumBuyPrice,
        uint256[] memory sellNftIds,
        uint256[] memory sellLps,
        uint256 minimumSellPrice
    ) external returns (uint256);
}
