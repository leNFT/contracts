// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.8.15;

import {INativeTokenVault} from "../interfaces/INativeTokenVault.sol";
import {INFTOracle} from "../interfaces/INFTOracle.sol";
import {PercentageMath} from "../libraries/math/PercentageMath.sol";
import {DataTypes} from "../libraries/types/DataTypes.sol";
import {CollectionLogic} from "../libraries/logic/CollectionLogic.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IAddressesProvider} from "../interfaces/IAddressesProvider.sol";
import {Trustus} from "./Trustus.sol";
import "hardhat/console.sol";

contract NFTOracle is INFTOracle, Ownable, Trustus {
    mapping(address => DataTypes.CollectionData) private _collections;

    uint256 public immutable _maxPriceDeviation;
    uint256 public immutable _minUpdateTime;
    IAddressesProvider private _addressProvider;

    using CollectionLogic for DataTypes.CollectionData;

    constructor(
        IAddressesProvider addressProvider,
        uint256 maxPriceDeviation,
        uint256 minUpdateTime
    ) {
        _addressProvider = addressProvider;
        _maxPriceDeviation = maxPriceDeviation;
        _minUpdateTime = minUpdateTime;
    }

    // Get the max collaterization price for a collection (10000 = 100%)
    function getCollectionMaxCollaterization(address collection)
        external
        view
        override
        returns (uint256)
    {
        return _collections[collection].maxCollaterization;
    }

    // Get the price for a certain token
    function getTokenETHPrice(
        address collection,
        uint256 tokenId,
        bytes32 request,
        TrustusPacket calldata packet
    ) external view override verifyPacket(request, packet) returns (uint256) {
        return _getTokenETHPrice(collection, tokenId, packet);
    }

    // Get the max collaterization for a certain collection and a certain user (includes boost) in ETH
    function getTokenMaxETHCollateral(
        address user,
        address collection,
        uint256 tokenId,
        bytes32 request,
        TrustusPacket calldata packet
    ) external view override verifyPacket(request, packet) returns (uint256) {
        uint256 voteCollaterizationBoost = INativeTokenVault(
            _addressProvider.getNativeTokenVault()
        ).getVoteCollateralizationBoost(user, collection);

        uint256 tokenPrice = _getTokenETHPrice(collection, tokenId, packet);

        return
            PercentageMath.percentMul(
                tokenPrice,
                _collections[collection].maxCollaterization +
                    voteCollaterizationBoost
            );
    }

    function addSupportedCollection(
        address collection,
        uint256 maxCollaterization
    ) external onlyOwner {
        _collections[collection].init();
        //Set the max collaterization
        _collections[collection].setMaxCollaterization(maxCollaterization);
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

    // Gets the token value sent by the off-chain server by unpacking the packet relayed by the caller
    function _getTokenETHPrice(
        address collection,
        uint256 tokenId,
        TrustusPacket calldata packet
    ) internal pure returns (uint256) {
        DataTypes.TokenPrice memory priceParams = abi.decode(
            packet.payload,
            (DataTypes.TokenPrice)
        );
        // Make sure the request is for the right token
        require(
            collection == priceParams.collection,
            "Request collection and collection don't coincide"
        );
        require(
            tokenId == priceParams.tokenId,
            "Request tokenId and tokenId don't coincide"
        );

        return priceParams.amount;
    }

    function setTrustedPriceSource(address signer) external {
        _setIsTrusted(signer, true);
    }

    function isSourceTrusted(address signer) external view returns (bool) {
        return (_isTrusted(signer));
    }
}
