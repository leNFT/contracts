// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.8.17;

import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {ERC721Enumerable} from "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import {IERC721Metadata} from "@openzeppelin/contracts/token/ERC721/extensions/IERC721Metadata.sol";

contract TestNFT is IERC721Metadata, ERC721Enumerable {
    event Mint(address owner, uint256 tokenId);

    constructor(string memory name, string memory symbol)
        ERC721(name, symbol)
    {}

    function mint(address owner) external returns (uint256) {
        uint256 tokenId = super.totalSupply();
        super._mint(owner, tokenId);

        emit Mint(owner, tokenId);

        return tokenId;
    }

    function tokenURI(uint256)
        public
        pure
        override(ERC721, IERC721Metadata)
        returns (string memory)
    {
        return
            "https://raw.githubusercontent.com/leNFT/interface/main/public/lettering_logo_square_small.png";
    }
}
