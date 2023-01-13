//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;

interface ISwapRouter {
    function approveTradingPool(address token, address tradingPool) external;
}
