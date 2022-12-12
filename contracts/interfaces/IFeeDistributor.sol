//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;

interface IFeeDistributor {
    function addFeesToEpoch(address token, uint256 amount) external;

    function claim(address token) external returns (uint256);
}
