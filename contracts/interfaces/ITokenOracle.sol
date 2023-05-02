//SPDX-License-Identifier: Unlicense
pragma solidity 0.8.19;

interface ITokenOracle {
    function isTokenSupported(address token) external view returns (bool);

    function getTokenETHPrice(
        address tokenAddress
    ) external view returns (uint256);

    function addTokenETHDataFeed(address token, address priceFeed) external;

    function setTokenETHPrice(address tokenAddress, uint256 price) external;

    function getPricePrecision() external pure returns (uint256);
}
