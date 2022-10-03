//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;

import {IERC721Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC721/IERC721Upgradeable.sol";

interface IGenesisNFT is IERC721Upgradeable {
    event Mint(address owner, uint256 tokenId);
    event Burn(uint256 tokenId);

    function getLTVBoost() external view returns (uint256);

    function setActiveState(uint256 tokenId, bool newState) external;

    function getActiveState(uint256 tokenId) external view returns (bool);
}
