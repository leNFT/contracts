//SPDX-License-Identifier: Unlicense
pragma solidity 0.8.19;

interface IFeeDistributor {
    function checkpoint(address token) external;
}
