// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.8.19;

import {INFTOracle} from "../../interfaces/INFTOracle.sol";
import {DataTypes} from "../../libraries/types/DataTypes.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Trustus} from "../Trustus/Trustus.sol";

/// @title NFTOracle contract
/// @dev This contract provides a mechanism for obtaining the ETH value of NFT tokens  using Trustus as the off-chain price oracle.
/// @dev Trustus provides a mechanism to sign, relay and verify off-chain data.
contract NFTOracle is INFTOracle, Ownable, Trustus {
    /// @notice Returns the ETH value of a collection of NFT tokens.
    /// @param collection The address of the collection contract
    /// @param tokenIds The IDs of the tokens whose value will be returned
    /// @param request The hash of the packet relayed by the caller
    /// @param packet The packet relayed by the caller
    /// @return The ETH value of the specified tokens
    function getTokensETHPrice(
        address collection,
        uint256[] memory tokenIds,
        bytes32 request,
        TrustusPacket calldata packet
    ) external view override returns (uint256) {
        return _getTokensETHPrice(collection, tokenIds, request, packet);
    }

    /// @notice Gets the token value sent by the off-chain server by unpacking the packet relayed by the caller.
    /// @param collection The address of the collection contract
    /// @param tokenIds The IDs of the tokens whose value will be returned
    /// @param request The hash of the packet relayed by the caller
    /// @param packet The packet relayed by the caller
    /// @return The ETH value of the specified tokens
    function _getTokensETHPrice(
        address collection,
        uint256[] memory tokenIds,
        bytes32 request,
        TrustusPacket calldata packet
    ) internal view verifyPacket(request, packet) returns (uint256) {
        DataTypes.AssetsPrice memory priceParams = abi.decode(
            packet.payload,
            (DataTypes.AssetsPrice)
        );
        // Make sure the request is for the right token
        require(
            collection == priceParams.collection,
            "NFTO:GTEP:COLLECTION_MISMATCH"
        );

        // Make sure the tokens ids coincide
        require(
            tokenIds.length == priceParams.tokenIds.length,
            "NFTO:GTEP:TOKENS_LENGTH_MISMATCH"
        );
        for (uint i = 0; i < tokenIds.length; i++) {
            require(
                tokenIds[i] == priceParams.tokenIds[i],
                "NFTO:GTEP:TOKEN_ID_MISMATCH"
            );
        }

        return priceParams.amount;
    }

    /// @notice Allows the owner to set whether a signer is trusted or not.
    /// @param signer The address of the signer
    /// @param isTrusted_ Whether the signer is trusted or not
    function setTrustedPriceSigner(
        address signer,
        bool isTrusted_
    ) external onlyOwner {
        _setIsTrusted(signer, isTrusted_);
    }

    /// @notice Checks whether a signer is trusted to provide token price information
    /// @param signer The address of the signer to check
    /// @return A boolean indicating whether the signer is trusted or not
    function isTrustedSigner(address signer) external view returns (bool) {
        return (_isTrusted(signer));
    }
}
