//SPDX-License-Identifier: Unlicense
pragma solidity 0.8.19;

import {DataTypes} from "../libraries/types/DataTypes.sol";

interface ITradingPool {
    event AddLiquidity(
        address indexed user,
        uint256 indexed id,
        DataTypes.LPType indexed lpType,
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
        DataTypes.LPType lpType,
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

    function getLpCount() external view returns (uint256);

    function nftToLp(uint256 nftId) external view returns (uint256);

    function getToken() external view returns (address);

    function getNFT() external view returns (address);
}
