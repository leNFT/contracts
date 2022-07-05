//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;

interface INFTOracle {
    function getNftFloorPrice(address nftCollection)
        external
        view
        returns (uint256);

    function getCollectionMaxCollateralization(address nftCollection)
        external
        view
        returns (uint256);

    function isNftSupported(address collection) external returns (bool);
}
