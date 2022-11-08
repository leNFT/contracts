//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;

interface INativeToken {
    function mintGenesisTokens(address receiver, uint256 amount) external;

    function mintStakingRewardTokens(uint256 amount) external;
}
