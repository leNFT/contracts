//SPDX-License-Identifier: Unlicense
pragma solidity 0.8.19;

interface IGauge {
    event Claim(address indexed user, uint256 amount);

    function getLPToken() external view returns (address);
}
