//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;

interface INativeToken {
    function mintGenesisTokens(address receiver, uint256 amount) external;

    function mintGaugeRewards(address receiver, uint256 amount) external;

    function getEpochGaugeRewards(
        uint256 epoch
    ) external view returns (uint256);
}
