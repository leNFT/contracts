// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.8.19;

import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import {ITokenOracle} from "../../interfaces/ITokenOracle.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/// @title TokenOracle
/// @author leNFT
/// @notice A contract that provides the ETH price for a given token based on a data feed or previously set price
/// @dev This contract implements the ITokenOracle interface and inherits from Ownable contract
/// @dev The contract uses Chainlink's AggregatorV3Interface to get token prices from data feeds
/// @dev The contract also defines a constant PRICE_PRECISION which is used to convert prices to the appropriate precision
contract TokenOracle is ITokenOracle, Ownable {
    uint256 internal constant PRICE_PRECISION = 1e18;
    mapping(address => uint256) private _tokenPrices;
    mapping(address => address) private _priceFeeds;

    /// @notice Check if a token is supported by the oracle (has a data feed or a previously set price)
    /// @param token The address of the token to check
    /// @return true if the token is supported, false otherwise
    function isTokenSupported(
        address token
    ) external view override returns (bool) {
        return _isTokenSupported(token);
    }

    /// @notice Internal function to check if a token is supported by the oracle
    /// @param token The address of the token to check
    /// @return true if the token is supported, false otherwise
    function _isTokenSupported(address token) internal view returns (bool) {
        return _priceFeeds[token] != address(0) || _tokenPrices[token] != 0;
    }

    /// @notice Get the ETH price of a token
    /// @param token The address of the token to get the price for
    /// @return The ETH price of the token
    /// @dev If a data feed is available, the price is returned from the data feed
    /// @dev If there's no data feed we return the previously set price on the mapping _tokenPrices[] set by the function setTokenETHPrice()
    function getTokenETHPrice(
        address token
    ) external view override returns (uint256, uint256) {
        // Make sure the token price is available in the contract
        require(_isTokenSupported(token), "TO:GTEP:TOKEN_NOT_SUPPORTED");

        // If a data feed is available return price from it
        if (_priceFeeds[token] != address(0)) {
            AggregatorV3Interface priceFeed = AggregatorV3Interface(
                _priceFeeds[token]
            );

            uint256 feedPrecision = 10 ** priceFeed.decimals();

            (, int price, , , ) = priceFeed.latestRoundData();

            return (
                (uint256(price) * PRICE_PRECISION) / feedPrecision,
                PRICE_PRECISION
            );
        }

        // If there's no data feed we return the previously set price
        return (_tokenPrices[token], PRICE_PRECISION);
    }

    /// @notice Set a data feed for a token
    /// @param token The address of the token to add a data feed for
    /// @param priceFeed The address of the Chainlink price feed for the token
    /// @dev Data feeds should return the price of the token in relation to ETH (e.g. 1 ETH = 1620.15597772 USDC)
    function setTokenETHDataFeed(
        address token,
        address priceFeed
    ) external override onlyOwner {
        _priceFeeds[token] = priceFeed;
    }

    /// @notice Set the ETH price for a token
    /// @param token The address of the token to set the price for
    /// @param price The ETH price of the token
    function setTokenETHPrice(
        address token,
        uint256 price
    ) external override onlyOwner {
        _tokenPrices[token] = price;
    }
}
