//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;

interface INativeToken {
    event DistributeRewards(uint256 _amount);

    function mintGenesisTokens(address receiver, uint256 amount) external;
}
