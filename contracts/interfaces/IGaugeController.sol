//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;

interface IGaugeController {
    function isGauge(address gauge) external view returns (bool);
}
