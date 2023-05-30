// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.8.19;

import {IAddressProvider} from "../interfaces/IAddressProvider.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @title Trading Pool Contract
/// @notice A contract that enables the creation of liquidity pools and the trading of NFTs and ERC20 tokens.
/// @dev This contract manages liquidity pairs, each consisting of a set of NFTs and an ERC20 token, as well as the trading of these pairs.
contract NativeTokenFaucet {
    uint public constant FAUCET_DRIP = 1000e18; // Drips 1000 LE tokens per request

    IAddressProvider private immutable _addressProvider;

    constructor(IAddressProvider addressProvider) {
        _addressProvider = addressProvider;
    }

    function drip(address account) external {
        // Make sure the faucet has enough balance
        require(
            IERC20(_addressProvider.getNativeToken()).balanceOf(
                address(this)
            ) >= FAUCET_DRIP,
            "NTF:D:NOT_ENOUGH_BALANCE"
        );

        // Send 1000 LE tokens to the account from the faucet's balance
        IERC20(_addressProvider.getNativeToken()).transfer(
            account,
            FAUCET_DRIP
        );
    }
}
