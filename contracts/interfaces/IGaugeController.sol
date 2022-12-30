//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;

interface IGaugeController {
    function isGauge(address gauge) external view returns (bool);

    event Vote(address indexed user, address indexed gauge, uint256 weight);

    event AddGauge(address indexed reserve, address indexed gauge);

    event RemoveGauge(address indexed reserve, address indexed gauge);
}
