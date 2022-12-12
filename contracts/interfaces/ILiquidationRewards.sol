//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;

import {DataTypes} from "../libraries/types/DataTypes.sol";
import {IAddressesProvider} from "../interfaces/IAddressesProvider.sol";

interface ILiquidationRewards {
    function getLiquidationReward(
        address lendingPool,
        uint256 lendingPoolTokenPrice,
        uint256 assetPrice,
        uint256 liquidationPrice
    ) external view returns (uint256);

    function sendLiquidationReward(address liquidator, uint256 amount) external;
}
