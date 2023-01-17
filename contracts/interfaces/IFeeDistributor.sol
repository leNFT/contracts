//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;

interface IFeeDistributor {
    function checkpoint(address token) external;

    function claim(address token) external returns (uint256);
}
