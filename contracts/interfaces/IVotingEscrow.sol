//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;

import {DataTypes} from "../libraries/types/DataTypes.sol";
import {IAddressesProvider} from "../interfaces/IAddressesProvider.sol";

interface IVotingEscrow {
    function lockHistoryLength(uint256 tokenId) external view returns (uint256);

    function epochPeriod() external pure returns (uint256);

    function epoch(uint256 timestamp) external view returns (uint256);

    function epochTimestamp(uint256 epoch_) external returns (uint256);

    function writeTotalWeightHistory() external;

    function getLockHistoryPoint(
        uint256 tokenId,
        uint256 index
    ) external view returns (DataTypes.Point memory);

    function getLockedRatioAt(uint256 _epoch) external returns (uint256);

    function totalWeightAt(uint256 epoch_) external returns (uint256);

    function totalWeight() external returns (uint256);

    function userWeight(address user) external view returns (uint256);

    function createLock(
        address receiver,
        uint256 amount,
        uint256 unlockTime
    ) external;

    function locked(
        uint256 tokenId
    ) external view returns (DataTypes.LockedBalance memory);
}
