//SPDX-License-Identifier: Unlicense
pragma solidity 0.8.19;

import {IERC721Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC721/IERC721Upgradeable.sol";

interface IGenesisNFT is IERC721Upgradeable {
    event Mint(address owner, uint256 tokenId);
    event Burn(uint256 tokenId);

    function getMaxLTVBoost() external view returns (uint256);

    function setLockedState(uint256 tokenId, bool newState) external;

    function getLockedState(uint256 tokenId) external view returns (bool);

    function isLoanOperatorApproved(
        address owner,
        address operator
    ) external view returns (bool);
}
