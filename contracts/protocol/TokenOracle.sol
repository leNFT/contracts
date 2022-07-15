// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.8.15;

import {ITokenOracle} from "../interfaces/ITokenOracle.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import "hardhat/console.sol";

contract TokenOracle is ITokenOracle, Ownable {
    mapping(address => uint256) private _tokenPrices;

    function getTokenPrice(address tokenAddress)
        external
        view
        override
        returns (uint256)
    {
        return _tokenPrices[tokenAddress];
    }

    function setTokenPrice(address tokenAddress, uint256 price)
        external
        override
    {
        _tokenPrices[tokenAddress] = price;
    }
}
