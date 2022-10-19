// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.8.15;

import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import {ITokenOracle} from "../interfaces/ITokenOracle.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import "hardhat/console.sol";

contract TokenOracle is ITokenOracle, Ownable {
    uint256 internal constant PRICE_PRECISION = 10**18;
    mapping(address => uint256) private _tokenPrices;
    mapping(address => address) private _priceFeeds;

    function isTokenSupported(address token) external view returns (bool) {
        return _isTokenSupported(token);
    }

    function _isTokenSupported(address token) internal view returns (bool) {
        return _priceFeeds[token] != address(0) || _tokenPrices[token] != 0;
    }

    function getTokenETHPrice(address token)
        external
        view
        override
        returns (uint256)
    {
        // Make sure the token price is available in the contract
        require(_isTokenSupported(token), "Token not supported by Oracle.");

        // If a data feed is available return price from it
        if (_priceFeeds[token] != address(0)) {
            AggregatorV3Interface priceFeed = AggregatorV3Interface(
                _priceFeeds[token]
            );

            uint256 feedPrecision = 10**priceFeed.decimals();

            (, int price, , , ) = priceFeed.latestRoundData();

            return uint256(price) * (PRICE_PRECISION / feedPrecision);
        }

        // If there's no data feed we return the previously set price
        return _tokenPrices[token];
    }

    // Data feeds should return the price of the token in relation to ETH (e.g. 1 ETH = 1620.15597772 USDC)
    function addTokenETHDataFeed(address token, address priceFeed)
        external
        override
        onlyOwner
    {
        _priceFeeds[token] = priceFeed;
    }

    function setTokenETHPrice(address token, uint256 price)
        external
        override
        onlyOwner
    {
        _tokenPrices[token] = price;
    }

    function getPricePrecision() external pure returns (uint256) {
        return PRICE_PRECISION;
    }
}
