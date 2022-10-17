// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.8.15;

import {IERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import {SafeERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import {DataTypes} from "../types/DataTypes.sol";
import {IReserve} from "../../interfaces/IReserve.sol";
import {ValidationLogic} from "./ValidationLogic.sol";
import {IAddressesProvider} from "../../interfaces/IAddressesProvider.sol";
import "hardhat/console.sol";

library SupplyLogic {
    using SafeERC20Upgradeable for IERC20Upgradeable;

    function deposit(address reserve, uint256 amount) external {
        // Verify if withdrawal conditions are met
        ValidationLogic.validateDeposit(reserve, amount);

        // Find how many tokens the reserve should mint
        uint256 reserveTokenAmount;
        if (IReserve(reserve).totalSupply() == 0) {
            reserveTokenAmount = amount;
        } else {
            reserveTokenAmount =
                (amount * IReserve(reserve).totalSupply()) /
                (IReserve(reserve).getUnderlyingBalance() +
                    IReserve(reserve).getDebt());
        }

        console.log("msg.sender", msg.sender);
        console.log("reserveTokenAmount", reserveTokenAmount);

        IReserve(reserve).depositUnderlying(msg.sender, amount);
        IReserve(reserve).mint(msg.sender, reserveTokenAmount);
    }

    function withdraw(
        IAddressesProvider addressesProvider,
        address reserve,
        address depositor,
        uint256 amount
    ) external {
        // Verify if withdrawal conditions are met
        ValidationLogic.validateWithdrawal(addressesProvider, reserve, amount);

        // Find how many tokens the reserve should burn
        uint256 reserveTokenAmount;
        if (IReserve(reserve).totalSupply() == 0) {
            reserveTokenAmount = amount;
        } else {
            reserveTokenAmount =
                (amount * IReserve(reserve).totalSupply()) /
                (IReserve(reserve).getUnderlyingBalance() +
                    IReserve(reserve).getDebt());
        }

        assert(reserveTokenAmount > 0);

        IReserve(reserve).burn(msg.sender, reserveTokenAmount);
        IReserve(reserve).withdrawUnderlying(depositor, amount);
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
