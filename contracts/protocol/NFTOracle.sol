// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.8.17;

import {INFTOracle} from "../interfaces/INFTOracle.sol";
import {PercentageMath} from "../libraries/math/PercentageMath.sol";
import {DataTypes} from "../libraries/types/DataTypes.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IAddressesProvider} from "../interfaces/IAddressesProvider.sol";
import {Trustus} from "./Trustus/Trustus.sol";
import {INativeTokenVault} from "../interfaces/INativeTokenVault.sol";
import "hardhat/console.sol";

contract NFTOracle is INFTOracle, Ownable, Trustus {
    IAddressesProvider private _addressProvider;

    constructor(IAddressesProvider addressProvider) {
        _addressProvider = addressProvider;
    }

    // Get the price for a certain token
    function getTokenETHPrice(
        address collection,
        uint256 tokenId,
        bytes32 request,
        TrustusPacket calldata packet
    ) external view override returns (uint256) {
        return _getTokenETHPrice(collection, tokenId, request, packet);
    }

    // Gets the token value sent by the off-chain server by unpacking the packet relayed by the caller
    function _getTokenETHPrice(
        address collection,
        uint256 tokenId,
        bytes32 request,
        TrustusPacket calldata packet
    ) internal view verifyPacket(request, packet) returns (uint256) {
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

    function setTrustedPriceSigner(address signer, bool isTrusted)
        external
        onlyOwner
    {
        _setIsTrusted(signer, isTrusted);
    }

    function isTrustedSigner(address signer) external view returns (bool) {
        return (_isTrusted(signer));
    }
}
