//SPDX-License-Identifier: Unlicense
pragma solidity 0.8.19;

interface IGauge {
    function getLPToken() external view returns (address);
}
