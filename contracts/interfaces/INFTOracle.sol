//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;

interface INFTOracle {
    function getCollectionFloorPrice(address collection)
        external
        view
        returns (uint256);

    function getMaxCollateral(address user, address collection)
        external
        returns (uint256);

    function isCollectionSupported(address collection) external returns (bool);
}
