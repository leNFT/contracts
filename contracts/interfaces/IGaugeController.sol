//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;

interface IGaugeController {
    event Vote(address indexed user, address indexed gauge, uint256 weight);

    event AddGauge(address indexed gauge, address indexed liquidityPool);

    event RemoveGauge(address indexed gauge, address indexed liquidityPool);

    function isGauge(address gauge) external view returns (bool);
}
