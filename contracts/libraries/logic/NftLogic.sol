// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.8.15;

import {DataTypes} from "../types/DataTypes.sol";

library NftLogic {
    function init(DataTypes.NftData storage nftData) internal {
        nftData.supported = true;
    }

    function setMaxCollaterization(
        DataTypes.NftData storage nftData,
        uint256 maxCollaterization
    ) internal {
        nftData.maxCollaterization = maxCollaterization;
    }

    function setFloorPrice(
        DataTypes.NftData storage nftData,
        uint256 floorPrice,
        uint256 timestamp
    ) internal {
        nftData.floorPrice = floorPrice;
        nftData.lastUpdateTimestamp = timestamp;
    }
}
