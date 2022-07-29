// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.8.15;

import {DataTypes} from "../types/DataTypes.sol";

library CollectionLogic {
    function init(DataTypes.CollectionData storage collectionData) internal {
        collectionData.supported = true;
    }

    function setMaxCollaterization(
        DataTypes.CollectionData storage collectionData,
        uint256 maxCollaterization
    ) internal {
        collectionData.maxCollaterization = maxCollaterization;
    }
}
