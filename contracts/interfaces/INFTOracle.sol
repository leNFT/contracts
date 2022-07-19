//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;

interface INFTOracle {
    function getCollectionETHFloorPrice(address collection)
        external
        view
        returns (uint256);

    function getCollectionMaxCollaterization(address collection)
        external
        view
        returns (uint256);

    function getMaxETHCollateral(address user, address collection)
        external
        view
        returns (uint256);

    function isCollectionSupported(address collection)
        external
        view
        returns (bool);
}
