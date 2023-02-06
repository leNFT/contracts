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
        uint256 spotPrice,
        address curve,
        uint256 delta,
        uint256 fee
    );
    event RemoveLiquidity(address indexed user, uint256 indexed lpId);

    event Buy(address indexed user, uint256[] nftIds, uint256 price);

    event Sell(address indexed user, uint256[] nftIds, uint256 price);

    event SetLpSpotPrice(
        address indexed user,
        uint256 indexed lpId,
        uint256 spotPrice
    );

    event SetLpPricingCurve(
        address indexed user,
        uint256 indexed lpId,
        address curve,
        uint256 delta
    );

    event SetLpFee(address indexed user, uint256 indexed lpId, uint256 fee);

    function addLiquidity(
        address receiver,
        uint256[] memory nftIds,
        uint256 tokenAmount,
        uint256 initialPrice,
        address curve,
        uint256 delta,
        uint256 fee
    ) external;

    function removeLiquidity(uint256 lpId) external;

    function removeLiquidityBatch(uint256[] memory lpIds) external;

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
