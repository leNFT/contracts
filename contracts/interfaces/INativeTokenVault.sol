//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;

import {DataTypes} from "../libraries/types/DataTypes.sol";
import {IMarketAddressesProvider} from "../interfaces/IMarketAddressesProvider.sol";

interface INativeTokenVault {
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

    function getUserFreeVotes(address user) external view returns (uint256);

    function getLockedBalance() external view returns (uint256);

    function getUserCollectionVotes(address user, address collection)
        external
        view
        returns (uint256);
}
