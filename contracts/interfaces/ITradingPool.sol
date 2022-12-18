//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;

import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {DataTypes} from "../libraries/types/DataTypes.sol";

interface ITradingPool is IERC721 {
    function getLP(
        uint256 lpId
    ) external view returns (DataTypes.LiquidityPair memory);
}
