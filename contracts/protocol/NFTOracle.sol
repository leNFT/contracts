// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.8.15;

import {INativeTokenVault} from "../interfaces/INativeTokenVault.sol";
import {INFTOracle} from "../interfaces/INFTOracle.sol";
import {PercentageMath} from "../libraries/math/PercentageMath.sol";
import {DataTypes} from "../libraries/types/DataTypes.sol";
import {CollectionLogic} from "../libraries/logic/CollectionLogic.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IMarketAddressesProvider} from "../interfaces/IMarketAddressesProvider.sol";
import "hardhat/console.sol";

contract NFTOracle is INFTOracle, Ownable {
    mapping(address => DataTypes.CollectionData) private _collections;

    uint256 public immutable _maxPriceDeviation;
    uint256 public immutable _minUpdateTime;
    IMarketAddressesProvider private _addressProvider;

    using CollectionLogic for DataTypes.CollectionData;

    constructor(
        IMarketAddressesProvider addressProvider,
        uint256 maxPriceDeviation,
        uint256 minUpdateTime
    ) {
        _addressProvider = addressProvider;
        _maxPriceDeviation = maxPriceDeviation;
        _minUpdateTime = minUpdateTime;
    }

    // Get the floor price for a collection
    function getCollectionFloorPrice(address collection)
        external
        view
        override
        returns (uint256)
    {
        return _collections[collection].floorPrice;
    }

    // Get the max collaterization for a certain collectin
    function getMaxCollateral(address user, address collection)
        external
        view
        override
        returns (uint256)
    {
        uint256 collaterizationBoost = INativeTokenVault(
            _addressProvider.getNativeTokenVault()
        ).getCollateralizationBoost(user, collection);
        return
            PercentageMath.percentMul(
                _collections[collection].floorPrice,
                _collections[collection].maxCollaterization +
                    collaterizationBoost
            );
    }

    // floor price with 18 decimals
    function addSupportedCollection(
        address collection,
        uint256 floorPrice,
        uint256 maxCollaterization
    ) external onlyOwner {
        _collections[collection].init();
        //Set the max collaterization
        _collections[collection].setMaxCollaterization(maxCollaterization);
        // Update the nft floor price data
        _collections[collection].setFloorPrice(floorPrice, block.timestamp);
    }

    function removeSupportedCollection(address collection) external onlyOwner {
        delete _collections[collection];
    }

    function isCollectionSupported(address collection)
        external
        view
        override
        returns (bool)
    {
        return _collections[collection].supported;
    }

    function addFloorPriceData(address collection, uint256 floorPrice)
        public
        onlyOwner
    {
        _addFloorPriceData(collection, floorPrice);
    }

    function batchAddFloorPriceData(
        address[] calldata collection,
        uint256[] calldata floorPrice
    ) public onlyOwner {
        for (uint256 i = 0; i < collection.length; i++) {
            _addFloorPriceData(collection[i], floorPrice[i]);
        }
    }

    function _addFloorPriceData(address collection, uint256 floorPrice)
        internal
    {
        require(_collections[collection].supported, "Unsupported Collection");

        require(
            (block.timestamp - _collections[collection].lastUpdateTimestamp) >
                _minUpdateTime,
            "Updating time too short"
        );

        // FInd if the price deviated too much from last price
        uint256 newFloorPrice = floorPrice;
        uint256 priceDeviation = (PercentageMath.PERCENTAGE_FACTOR *
            (_collections[collection].floorPrice - floorPrice)) /
            _collections[collection].floorPrice;

        if (priceDeviation > _maxPriceDeviation) {
            if (_collections[collection].floorPrice > floorPrice) {
                newFloorPrice = PercentageMath.percentMul(
                    _collections[collection].floorPrice,
                    PercentageMath.PERCENTAGE_FACTOR - _maxPriceDeviation
                );
            } else if (_collections[collection].floorPrice < floorPrice) {
                newFloorPrice = newFloorPrice = PercentageMath.percentMul(
                    _collections[collection].floorPrice,
                    PercentageMath.PERCENTAGE_FACTOR + _maxPriceDeviation
                );
            } else {
                newFloorPrice = _collections[collection].floorPrice;
            }
        }

        // Update the nft floor price data
        _collections[collection].setFloorPrice(newFloorPrice, block.number);
    }
}
