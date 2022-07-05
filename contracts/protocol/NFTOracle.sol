// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.8.15;

import {INFTOracle} from "../interfaces/INFTOracle.sol";
import {PercentageMath} from "../libraries/math/PercentageMath.sol";
import {DataTypes} from "../libraries/types/DataTypes.sol";
import {NftLogic} from "../libraries/logic/NftLogic.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract NFTOracle is INFTOracle, Ownable {
    mapping(address => DataTypes.NftData) private _nfts;

    uint256 public immutable _maxPriceDeviation;
    uint256 public immutable _minUpdateTime;

    using NftLogic for DataTypes.NftData;

    constructor(uint256 maxPriceDeviation, uint256 minUpdateTime) {
        _maxPriceDeviation = maxPriceDeviation;
        _minUpdateTime = minUpdateTime;
    }

    // Get the floor price for a collection
    function getNftFloorPrice(address nftCollection)
        external
        view
        override
        returns (uint256)
    {
        return _nfts[nftCollection].floorPrice;
    }

    // Get the max collaterization for a certain collectin
    function getCollectionMaxCollateralization(address collection)
        external
        view
        override
        returns (uint256)
    {
        return
            PercentageMath.percentMul(
                _nfts[collection].floorPrice,
                _nfts[collection].maxCollaterization
            );
    }

    // floor price with 18 decimals
    function addSupportedNft(
        address collection,
        uint256 floorPrice,
        uint256 maxCollaterization
    ) external onlyOwner {
        _nfts[collection].init();
        //Set the max collaterization
        _nfts[collection].setMaxCollaterization(maxCollaterization);
        // Update the nft floor price data
        _nfts[collection].setFloorPrice(floorPrice, block.timestamp);
    }

    function removeSupportedNft(address collection) external onlyOwner {
        delete _nfts[collection];
    }

    function isNftSupported(address collection)
        external
        view
        override
        returns (bool)
    {
        return _nfts[collection].supported;
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
        require(_nfts[collection].supported, "Unsupported Collection");

        require(
            (block.timestamp - _nfts[collection].lastUpdateTimestamp) >
                _minUpdateTime,
            "Updating time too short"
        );

        // FInd if the price deviated too much from last price
        uint256 priceDeviation = (_nfts[collection].floorPrice - floorPrice) /
            _nfts[collection].floorPrice;
        uint256 newFloorPrice;

        if (priceDeviation > _maxPriceDeviation) {
            if (_nfts[collection].floorPrice > floorPrice) {
                newFloorPrice =
                    (1 - _maxPriceDeviation) *
                    _nfts[collection].floorPrice;
            } else if (_nfts[collection].floorPrice < floorPrice) {
                newFloorPrice =
                    (1 + _maxPriceDeviation) *
                    _nfts[collection].floorPrice;
            } else {
                newFloorPrice = _nfts[collection].floorPrice;
            }
        }

        // Update the nft floor price data
        _nfts[collection].setFloorPrice(newFloorPrice, block.number);
    }
}
