//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;

import {Trustus} from "../protocol/Trustus.sol";

interface INFTOracle {
    function getCollectionMaxCollaterization(address collection)
        external
        view
        returns (uint256);

    function getTokenETHPrice(
        address collection,
        uint256 tokenId,
        bytes32 request,
        Trustus.TrustusPacket calldata packet
    ) external view returns (uint256);

    function getTokenMaxETHCollateral(
        address user,
        address collection,
        uint256 tokenId,
        bytes32 request,
        Trustus.TrustusPacket calldata packet
    ) external view returns (uint256);

    function isCollectionSupported(address collection)
        external
        view
        returns (bool);
}
