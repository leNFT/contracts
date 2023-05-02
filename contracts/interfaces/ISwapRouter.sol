//SPDX-License-Identifier: Unlicense
pragma solidity 0.8.19;

import {ITradingPool} from "./ITradingPool.sol";

interface ISwapRouter {
    function approveTradingPool(address token, address tradingPool) external;

    function swap(
        ITradingPool buyPool,
        ITradingPool sellPool,
        uint256[] memory buyNftIds,
        uint256 maximumBuyPrice,
        uint256[] memory sellNftIds,
        uint256[] memory sellLps,
        uint256 minimumSellPrice
    ) external returns (uint256);
}
