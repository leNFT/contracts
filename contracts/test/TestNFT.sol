// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.8.19;

import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {ERC721Enumerable} from "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import {IERC721Metadata} from "@openzeppelin/contracts/token/ERC721/extensions/IERC721Metadata.sol";
import {ERC165} from "@openzeppelin/contracts/utils/introspection/ERC165.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";

contract TestNFT is ERC165, IERC721Metadata, ERC721Enumerable {
    event Mint(address owner, uint256 tokenId);

    constructor(
        string memory name,
        string memory symbol // solhint-disable-next-line no-empty-blocks
    ) ERC721(name, symbol) {}

    function mint(address owner) external returns (uint256) {
        uint256 tokenId = super.totalSupply();
        super._mint(owner, tokenId);

        emit Mint(owner, tokenId);

        return tokenId;
    }

    function tokenURI(
        uint256
    ) public pure override(ERC721, IERC721Metadata) returns (string memory) {
        return
            "https://raw.githubusercontent.com/leNFT/interface/main/public/lettering_logo_square_small.png";
    }

    function supportsInterface(
        bytes4 interfaceId
    ) public view override(ERC165, ERC721Enumerable, IERC165) returns (bool) {
        return
            interfaceId == type(IERC721Metadata).interfaceId ||
            super.supportsInterface(interfaceId);
    }
}
