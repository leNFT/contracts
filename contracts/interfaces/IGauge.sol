//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;

interface IGauge {
    function lpToken() external view returns (address);
}
