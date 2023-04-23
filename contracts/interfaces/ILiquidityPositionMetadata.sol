//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;

interface ILiquidityPositionMetadata {
    function tokenURI(
        address tradingPool,
        uint256 tokenId
    ) external view returns (string memory);
}
