//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;

import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {DataTypes} from "../libraries/types/DataTypes.sol";

interface ITradingPool is IERC721 {
    event AddLiquidity(
        address indexed user,
        address indexed id,
        uint256 tokenAmount,
        uint256[] nftIds
    );
    event RemoveLiquidity(address indexed user, address indexed id);

    function getLP(
        uint256 lpId
    ) external view returns (DataTypes.LiquidityPair memory);
}
