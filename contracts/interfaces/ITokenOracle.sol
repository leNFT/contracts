//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;

interface ITokenOracle {
    function getTokenETHPrice(address tokenAddress)
        external
        view
        returns (uint256);

    function addTokenETHDataFeed(address token, address priceFeed) external;

    function setTokenETHPrice(address tokenAddress, uint256 price) external;

    function getPricePrecision() external pure returns (uint256);
}
