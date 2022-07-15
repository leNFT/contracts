//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;

interface ITokenOracle {
    function getTokenPrice(address tokenAddress)
        external
        view
        returns (uint256);

    function setTokenPrice(address tokenAddress, uint256 price) external;
}
