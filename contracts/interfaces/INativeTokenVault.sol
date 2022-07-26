//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;

import {DataTypes} from "../libraries/types/DataTypes.sol";
import {IAddressesProvider} from "../interfaces/IAddressesProvider.sol";

interface INativeTokenVault {
    event Deposit(address indexed user, uint256 amount);

    event Withdraw(address indexed user, uint256 amount);

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

    function deposit(uint256 amount) external;

    function withdraw(uint256 amount) external;

    function getMaximumWithdrawalAmount(address user)
        external
        view
        returns (uint256);

    function createWithdrawRequest(uint256 amount) external;

    function getWithdrawRequest(address user)
        external
        view
        returns (DataTypes.WithdrawRequest memory);

    function getCollateralizationBoost(address user, address collection)
        external
        view
        returns (uint256);

    function vote(uint256 amount, address collection) external;

    function removeVote(uint256 amount, address collection) external;

    function getUserFreeVotes(address user) external view returns (uint256);

    function getLockedBalance() external view returns (uint256);

    function getUserCollectionVotes(address user, address collection)
        external
        view
        returns (uint256);
}
