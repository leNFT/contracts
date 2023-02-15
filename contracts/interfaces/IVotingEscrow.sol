//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;

import {DataTypes} from "../libraries/types/DataTypes.sol";
import {IAddressesProvider} from "../interfaces/IAddressesProvider.sol";

interface IVotingEscrow {
    function userHistoryLength(address user) external view returns (uint256);

    function epochPeriod() external pure returns (uint256);

    function epoch(uint256 timestamp) external view returns (uint256);

    function epochTimestamp(uint256 epoch_) external returns (uint256);

    function getUserHistoryPoint(
        address user,
        uint256 index
    ) external view returns (DataTypes.Point memory);

    function totalSupplyAt(uint256 epoch_) external returns (uint256);

    function totalSupply() external returns (uint256);

    function balanceOf(address user) external view returns (uint256);

    function createLock(
        address receiver,
        uint256 amount,
        uint256 unlockTime
    ) external;

    function locked(
        address user
    ) external view returns (DataTypes.LockedBalance memory);
}
