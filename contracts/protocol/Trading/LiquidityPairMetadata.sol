// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Base64} from "@openzeppelin/contracts/utils/Base64.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {IERC721Metadata} from "@openzeppelin/contracts/token/ERC721/extensions/IERC721Metadata.sol";
import {ITradingPool} from "../../interfaces/ITradingPool.sol";
import {ILiquidityPairMetadata} from "../../interfaces/ILiquidityPairMetadata.sol";
import {DataTypes} from "../../libraries/types/DataTypes.sol";

/// @title LiquidityPair Metadata
/// @author leNFT dev (thanks to out.eth (@outdoteth))
/// @notice This contract is used to generate a liquidity pair's metadata.
contract LiquidityPairMetadata is ILiquidityPairMetadata {
    /// @notice Returns the metadata for a liquidity pair
    /// @param tradingPool The address of the trading pool of the liquidity pair.
    /// @param tokenId The liquidity pair's token ID.
    function tokenURI(
        address tradingPool,
        uint256 tokenId
    ) public view override returns (string memory) {
        // forgefmt: disable-next-item
        bytes memory metadata = abi.encodePacked(
            "{",
            '"name": "Liquidity Pair ',
            IERC721Metadata(ITradingPool(tradingPool).getNFT()).symbol(),
            IERC20Metadata(ITradingPool(tradingPool).getToken()).symbol(),
            " #",
            Strings.toString(tokenId),
            '",',
            '"description": "leNFT trading liquidity pair.",',
            '"image": ',
            '"data:image/svg+xml;base64,',
            Base64.encode(svg(tradingPool, tokenId)),
            '",',
            '"attributes": [',
            attributes(tradingPool, tokenId),
            "]",
            "}"
        );

        return
            string(
                abi.encodePacked(
                    "data:application/json;base64,",
                    Base64.encode(metadata)
                )
            );
    }

    /// @notice Returns the attributes for a liquidity pair encoded as json.
    /// @param tradingPool The address of the trading pool of the liquidity pair.
    /// @param tokenId The liquidity pair's token ID.
    function attributes(
        address tradingPool,
        uint256 tokenId
    ) public view returns (string memory) {
        DataTypes.LiquidityPair memory lp = ITradingPool(tradingPool).getLP(
            tokenId
        );

        // forgefmt: disable-next-item
        bytes memory _attributes = abi.encodePacked(
            trait("Pool address", Strings.toHexString(tradingPool)),
            ",",
            trait(
                "Token",
                Strings.toHexString(ITradingPool(tradingPool).getToken())
            ),
            ",",
            trait(
                "NFT",
                Strings.toHexString(ITradingPool(tradingPool).getNFT())
            ),
            ",",
            trait("Price", Strings.toString(lp.spotPrice)),
            ",",
            trait("Token balance", Strings.toString(lp.tokenAmount)),
            ",",
            trait("NFT balance", Strings.toString(lp.nftIds.length)),
            ",",
            trait("Curve", Strings.toHexString(lp.curve)),
            ",",
            trait("Delta", Strings.toString(lp.delta)),
            ",",
            trait("Fee", Strings.toString(lp.fee)),
            ",",
            trait("Type", Strings.toString(uint256(lp.lpType)))
        );

        return string(_attributes);
    }

    /// @notice Returns an svg image for a liquidity pair.
    /// @param tradingPool The address of the trading pool of the liquidity pair.
    /// @param tokenId The liquidity pair's token ID.
    function svg(
        address tradingPool,
        uint256 tokenId
    ) public view returns (bytes memory) {
        DataTypes.LiquidityPair memory lp = ITradingPool(tradingPool).getLP(
            tokenId
        );

        // break up svg building into multiple scopes to avoid stack too deep errors
        bytes memory _svg;
        {
            // forgefmt: disable-next-item
            _svg = abi.encodePacked(
                '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 400 400" style="width:100%;background:#eaeaea;fill:black;font-family:monospace">',
                '<text x="50%" y="24px" font-size="12" text-anchor="middle">',
                "leNFT Trading Pair ",
                IERC721Metadata(ITradingPool(tradingPool).getNFT()).symbol(),
                IERC20Metadata(ITradingPool(tradingPool).getToken()).symbol(),
                " #",
                Strings.toString(tokenId),
                "</text>",
                '<text x="24px" y="72px" font-size="8">',
                "Trading pool: ",
                Strings.toHexString(address(tradingPool)),
                "</text>",
                '<text x="24px" y="90px" font-size="8">',
                "NFT: ",
                IERC721Metadata(ITradingPool(tradingPool).getNFT()).name(),
                "</text>",
                '<text x="24px" y="108px" font-size="8">',
                "Token: ",
                IERC20Metadata(ITradingPool(tradingPool).getToken()).name(),
                "</text>"
            );
        }

        {
            _svg = abi.encodePacked(
                _svg,
                '<text x="24px" y="126px" font-size="8">',
                "Price: ",
                Strings.toString(lp.spotPrice),
                "</text>",
                '<text x="24px" y="144px" font-size="8">',
                "NFT Balance: ",
                Strings.toString(lp.nftIds.length),
                "</text>",
                '<text x="24px" y="162px" font-size="8">',
                "Token Balance: ",
                Strings.toString(lp.tokenAmount),
                "</text>"
            );
        }

        {
            _svg = abi.encodePacked(
                _svg,
                '<text x="24px" y="180px" font-size="8">',
                "Fee: ",
                Strings.toString(lp.fee),
                "</text>",
                '<text x="24px" y="198px" font-size="8">',
                "Curve: ",
                Strings.toHexString(lp.curve),
                "</text>",
                '<text x="24px" y="216px" font-size="8">',
                "Delta: ",
                Strings.toString(lp.delta),
                "</text>",
                "</svg>"
            );
        }

        return _svg;
    }

    function trait(
        string memory traitType,
        string memory value
    ) internal pure returns (string memory) {
        // forgefmt: disable-next-item
        return
            string(
                abi.encodePacked(
                    '{ "trait_type": "',
                    traitType,
                    '",',
                    '"value": "',
                    value,
                    '" }'
                )
            );
    }
}
