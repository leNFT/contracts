// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.8.17;

import {IERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import {SafeERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import {DataTypes} from "../types/DataTypes.sol";
import {IReserve} from "../../interfaces/IReserve.sol";
import {ValidationLogic} from "./ValidationLogic.sol";
import {IAddressesProvider} from "../../interfaces/IAddressesProvider.sol";
import "hardhat/console.sol";

library SupplyLogic {
    using SafeERC20Upgradeable for IERC20Upgradeable;

    function deposit(DataTypes.DepositParams memory params) external {
        // Verify if withdrawal conditions are met
        ValidationLogic.validateDeposit(params);

        // Find how many tokens the reserve should mint
        uint256 reserveTokenAmount;
        if (IReserve(params.reserve).totalSupply() == 0) {
            reserveTokenAmount = params.amount;
        } else {
            reserveTokenAmount =
                (params.amount * IReserve(params.reserve).totalSupply()) /
                (IReserve(params.reserve).getUnderlyingBalance() +
                    IReserve(params.reserve).getDebt());
        }

        console.log("msg.sender", msg.sender);
        console.log("reserveTokenAmount", reserveTokenAmount);

        IReserve(params.reserve).depositUnderlying(msg.sender, params.amount);
        IReserve(params.reserve).mint(msg.sender, reserveTokenAmount);
    }

    function withdraw(
        IAddressesProvider addressesProvider,
        DataTypes.WithdrawalParams memory params
    ) external {
        // Verify if withdrawal conditions are met
        ValidationLogic.validateWithdrawal(addressesProvider, params);

        // Find how many tokens the reserve should burn
        uint256 reserveTokenAmount;
        if (IReserve(params.reserve).totalSupply() == 0) {
            reserveTokenAmount = params.amount;
        } else {
            reserveTokenAmount =
                (params.amount * IReserve(params.reserve).totalSupply()) /
                (IReserve(params.reserve).getUnderlyingBalance() +
                    IReserve(params.reserve).getDebt());
        }

        assert(reserveTokenAmount > 0);

        IReserve(params.reserve).burn(msg.sender, reserveTokenAmount);
        IReserve(params.reserve).withdrawUnderlying(
            params.depositor,
            params.amount
        );
    }

    function maximumWithdrawalAmount(address reserve, address user)
        external
        view
        returns (uint256)
    {
        uint256 reserveTokenAmount = IReserve(reserve).balanceOf(user);
        uint256 maximumAmount;

        if (reserveTokenAmount == 0) {
            maximumAmount = 0;
        } else {
            maximumAmount =
                (reserveTokenAmount *
                    (IReserve(reserve).getUnderlyingBalance() +
                        IReserve(reserve).getDebt())) /
                IReserve(reserve).totalSupply();
        }

        return maximumAmount;
    }
}
