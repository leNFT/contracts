// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.8.15;

import {IERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import {SafeERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import {DataTypes} from "../types/DataTypes.sol";
import {IReserve} from "../../interfaces/IReserve.sol";

library SupplyLogic {
    using SafeERC20Upgradeable for IERC20Upgradeable;

    function deposit(
        mapping(address => address) storage reserves,
        address asset,
        uint256 amount
    ) external {
        address reserveAddress = reserves[asset];
        IReserve reserve = IReserve(reserveAddress);

        // Find how many tokens the reserve should mint
        uint256 reserveTokenAmount;
        if (reserve.totalSupply() == 0) {
            reserveTokenAmount = amount;
        } else {
            reserveTokenAmount =
                (amount * reserve.totalSupply()) /
                (reserve.getUnderlyingBalance() + reserve.getDebt());
        }

        reserve.depositUnderlying(msg.sender, amount);
        reserve.mint(msg.sender, reserveTokenAmount);
    }

    function maximumWithdrawalAmount(address reserveAddress, address user)
        external
        view
        returns (uint256)
    {
        IReserve reserve = IReserve(reserveAddress);
        uint256 reserveTokenAmount = reserve.balanceOf(user);
        uint256 maximumAmount;

        if (reserveTokenAmount == 0) {
            maximumAmount = 0;
        } else {
            maximumAmount =
                (reserveTokenAmount *
                    (reserve.getUnderlyingBalance() + reserve.getDebt())) /
                reserve.totalSupply();
        }

        return maximumAmount;
    }

    function withdraw(
        mapping(address => address) storage reserves,
        address asset,
        uint256 amount
    ) external {
        address reserveAddress = reserves[asset];
        IReserve reserve = IReserve(reserveAddress);

        // Find how many tokens the reserve should burn
        uint256 reserveTokenAmount;
        if (reserve.totalSupply() == 0) {
            reserveTokenAmount = amount;
        } else {
            reserveTokenAmount =
                (amount * reserve.totalSupply()) /
                (reserve.getUnderlyingBalance() + reserve.getDebt());
        }

        IReserve(reserveAddress).burn(msg.sender, reserveTokenAmount);

        IReserve(reserveAddress).withdrawUnderlying(msg.sender, amount);
    }
}
