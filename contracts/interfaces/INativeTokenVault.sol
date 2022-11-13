//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;

import {DataTypes} from "../libraries/types/DataTypes.sol";
import {IAddressesProvider} from "../interfaces/IAddressesProvider.sol";

interface INativeTokenVault {
    event DistributeRewards(uint256 amount);

    event Vote(
        address indexed user,
        address indexed collection,
        uint256 amount
    );

    event RemoveVote(
        address indexed user,
        address indexed collection,
        uint256 amount
    );

    function getWithdrawalRequest(address user)
        external
        view
        returns (DataTypes.WithdrawalRequest memory);

    function getLTVBoost(address user, address collection)
        external
        view
        returns (uint256);

    function vote(uint256 amount, address collection) external;

    function removeVote(uint256 amount, address collection) external;

    function getLiquidationReward(
        address reserve,
        uint256 reserveTokenPrice,
        uint256 assetPrice,
        uint256 liquidationPrice
    ) external view returns (uint256);

    function sendLiquidationReward(address liquidator, uint256 amount) external;

    function getUserFreeVotes(address user) external view returns (uint256);

    function getUserCollectionVotes(address user, address collection)
        external
        view
        returns (uint256);

    function getWithdrawalCoolingPeriod() external view returns (uint256);

    function getWithdrawalActivePeriod() external view returns (uint256);
}
