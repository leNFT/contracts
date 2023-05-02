//SPDX-License-Identifier: Unlicense
pragma solidity 0.8.19;

interface ILiquidityPairMetadata {
    function tokenURI(
        address tradingPool,
        uint256 tokenId
    ) external view returns (string memory);
}
