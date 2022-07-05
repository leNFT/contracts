// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.8.15;

import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {ERC721Enumerable} from "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";

contract TestNFT is ERC721Enumerable {
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
}
