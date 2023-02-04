// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.8.17;

import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {IAddressesProvider} from "../../interfaces/IAddressesProvider.sol";
import {ITradingPool} from "../../interfaces/ITradingPool.sol";
import {ISwapRouter} from "../../interfaces/ISwapRouter.sol";
import {ContextUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ContextUpgradeable.sol";
import {SafeERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import {IERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "hardhat/console.sol";

/// @title SwapRouter Contract
/// @author leNFT
/// @notice This contract is responsible for swapping between assets in different pools
contract SwapRouter is
    Initializable,
    ISwapRouter,
    OwnableUpgradeable,
    ReentrancyGuardUpgradeable
{
    IAddressesProvider private _addressProvider;

    using SafeERC20Upgradeable for IERC20Upgradeable;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

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
        uint256[] memory sellNftIds,
        uint256[] memory sellLps,
        uint256 minimumSellPrice
    ) external nonReentrant returns (uint256) {
        // Pools need to be different
        require(
            address(buyPool) != address(sellPool),
            "Pools need to be different."
        );
        // Pools need to have the same underlying token
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

        console.log("sellPrice", sellPrice);

        uint256 priceDiff = 0;
        if (maximumBuyPrice > minimumSellPrice) {
            priceDiff = maximumBuyPrice - minimumSellPrice;
            IERC20Upgradeable(sellPool.getToken()).safeTransferFrom(
                msg.sender,
                address(this),
                priceDiff
            );
        }

        uint256 buyPrice = buyPool.buy(msg.sender, buyNftIds, maximumBuyPrice);

        // If the price difference + sell price is greater than the buy price, return the difference to the user
        uint256 returnedAmount = 0;
        if (sellPrice + priceDiff > buyPrice) {
            returnedAmount = sellPrice + priceDiff - buyPrice;
            IERC20Upgradeable(sellPool.getToken()).safeTransfer(
                msg.sender,
                returnedAmount
            );
        }

        return returnedAmount;
    }

    function approveTradingPool(address token, address tradingPool) external {
        require(
            msg.sender == _addressProvider.getTradingPoolFactory(),
            "Only trading pool factory can approve trading pool."
        );
        IERC20Upgradeable(token).safeApprove(tradingPool, type(uint256).max);
    }
}
