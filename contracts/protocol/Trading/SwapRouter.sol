// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.8.17;

import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {IAddressesProvider} from "../../interfaces/IAddressesProvider.sol";
import {ITradingPool} from "../../interfaces/ITradingPool.sol";
import {ContextUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ContextUpgradeable.sol";
import {SafeERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import {IERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";

/// @title SwapRouter Contract
/// @author leNFT
/// @notice This contract is responsible for swapping between assets in different pools
contract SwapRouter is
    Initializable,
    OwnableUpgradeable,
    ReentrancyGuardUpgradeable
{
    IAddressesProvider private _addressProvider;

    using SafeERC20Upgradeable for IERC20Upgradeable;

    // Initialize the market
    function initialize(
        IAddressesProvider addressesProvider
    ) external initializer {
        __Ownable_init();
        _addressProvider = addressesProvider;
    }

    function swap(
        ITradingPool buyPool,
        ITradingPool sellPool,
        uint256[] memory buyNftIds,
        uint256 maximumBuyPrice,
        uint256 buyChange,
        uint256[] memory sellNftIds,
        uint256[] memory sellLps,
        uint256 minimumSellPrice
    ) external nonReentrant {
        // Pools need to be different but have the same underlying token
        require(
            address(buyPool) != address(sellPool),
            "Pools need to be different."
        );
        require(
            buyPool.getToken() == sellPool.getToken(),
            "Underlying token mismatch."
        );

        uint256 sellPrice = sellPool.sell(
            msg.sender,
            sellNftIds,
            sellLps,
            minimumSellPrice
        );

        if (buyChange > 0) {
            IERC20Upgradeable(sellPool.getToken()).safeTransferFrom(
                msg.sender,
                address(this),
                buyChange
            );
        }

        uint256 buyPrice = sellPool.buy(msg.sender, buyNftIds, maximumBuyPrice);

        //Send change back to user
        if (buyPrice > sellPrice + buyChange) {
            IERC20Upgradeable(sellPool.getToken()).safeTransfer(
                msg.sender,
                sellPrice + buyChange - buyPrice
            );
        }
    }
}
