//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;

interface INativeToken {
    function mintGenesisTokens(uint256 amount) external;

    function burnGenesisTokens(uint256 amount) external;

    function mintGaugeRewards(address receiver, uint256 amount) external;

    function getEpochRewards(uint256 epoch) external view returns (uint256);
}
