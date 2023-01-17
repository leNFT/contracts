//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;

interface ITradingPoolFactory {
    event CreateTradingPool(
        address indexed pool,
        address indexed nft,
        address indexed token
    );

    function getProtocolFee() external view returns (uint256);
}
