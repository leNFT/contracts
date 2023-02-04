//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;

import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {DataTypes} from "../libraries/types/DataTypes.sol";

interface ITradingPool is IERC721 {
    event AddLiquidity(
        address indexed user,
        uint256 indexed id,
        uint256[] nftIds,
        uint256 tokenAmount,
        address curve,
        uint256 delta,
        uint256 initalPrice
    );
    event RemoveLiquidity(address indexed user, uint256 indexed lpId);

    event Buy(address indexed user, uint256[] nftIds, uint256 price);

    event Sell(address indexed user, uint256[] nftIds, uint256 price);

    event SetLpPrice(address indexed user, uint256 indexed lpId, uint256 price);

    event SetLpPricingCurve(
        address indexed user,
        uint256 indexed lpId,
        address curve,
        uint256 delta
    );

    function addLiquidity(
        address receiver,
        uint256[] memory nftIds,
        uint256 tokenAmount,
        address curve,
        uint256 delta,
        uint256 initialPrice
    ) external;

    function removeLiquidity(uint256 lpId) external;

    function buy(
        address onBehalfOf,
        uint256[] memory nftIds,
        uint256 maximumPrice
    ) external returns (uint256);

    function sell(
        address onBehalfOf,
        uint256[] memory nftIds,
        uint256[] memory liquidityPairs,
        uint256 minimumPrice
    ) external returns (uint256);

    function getLP(
        uint256 lpId
    ) external view returns (DataTypes.LiquidityPair memory);

    function getToken() external view returns (address);

    function getNFT() external view returns (address);
}
