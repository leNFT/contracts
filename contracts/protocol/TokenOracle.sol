// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.8.15;

import {ITokenOracle} from "../interfaces/ITokenOracle.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import "hardhat/console.sol";

contract TokenOracle is ITokenOracle, Ownable {
    uint256 internal constant PRICE_PRECISION = 10**18;
    mapping(address => uint256) private _tokenPrices;

    function getTokenETHPrice(address tokenAddress)
        external
        view
        override
        returns (uint256)
    {
        return _tokenPrices[tokenAddress];
    }

    function setTokenETHPrice(address tokenAddress, uint256 price)
        external
        override
        onlyOwner
    {
        _tokenPrices[tokenAddress] = price;
    }

    function getPricePrecision() external pure returns (uint256) {
        return PRICE_PRECISION;
    }
}
