// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.8.19;

import {IAddressProvider} from "../../interfaces/IAddressProvider.sol";
import {ITradingPool} from "../../interfaces/ITradingPool.sol";
import {ITradingPoolFactory} from "../../interfaces/ITradingPoolFactory.sol";
import {ISwapRouter} from "../../interfaces/ISwapRouter.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";

/// @title SwapRouter Contract
/// @author leNFT
/// @notice This contract is responsible for swapping between assets in different pools
/// @dev Coordenates a buy and sell between two different trading pools
contract SwapRouter is ISwapRouter, ReentrancyGuard {
    IAddressProvider private immutable _addressProvider;

    using SafeERC20 for IERC20;

    /// @notice Constructor of the contract
    /// @param addressProvider The address of the addressProvider contract
    constructor(IAddressProvider addressProvider) {
        _addressProvider = addressProvider;
    }

    /// @notice Swaps tokens between two different trading pools
    /// @dev The pools must have the same underlying token
    /// @param buyPool The trading pool where the user will buy NFTs
    /// @param sellPool The trading pool where the user will sell NFTs
    /// @param buyNftIds The IDs of the NFTs that the user will buy
    /// @param maximumBuyPrice The maximum price that the user is willing to pay for the NFTs
    /// @param sellNftIds The IDs of the NFTs that the user will sell
    /// @param sellLps The amounts of liquidity provider tokens to be sold
    /// @param minimumSellPrice The minimum price that the user is willing to accept for the NFTs
    /// @return change The amount of tokens returned to the user
    function swap(
        ITradingPool buyPool,
        ITradingPool sellPool,
        uint256[] calldata buyNftIds,
        uint256 maximumBuyPrice,
        uint256[] calldata sellNftIds,
        uint256[] calldata sellLps,
        uint256 minimumSellPrice
    ) external nonReentrant returns (uint256 change) {
        // Pools need to be registered in the factory
        require(
            ITradingPoolFactory(_addressProvider.getTradingPoolFactory())
                .isTradingPool(address(buyPool)),
            "SR:S:INVALID_BUY_POOL"
        );
        if (address(buyPool) != address(sellPool)) {
            require(
                ITradingPoolFactory(_addressProvider.getTradingPoolFactory())
                    .isTradingPool(address(sellPool)),
                "SR:S:INVALID_SELL_POOL"
            );
            // Pools need to have the same underlying token
            require(
                buyPool.getToken() == sellPool.getToken(),
                "SR:S:DIFFERENT_TOKENS"
            );
        }

        uint256 sellPrice = sellPool.sell(
            msg.sender,
            sellNftIds,
            sellLps,
            minimumSellPrice
        );

        // If the buy price is greater than the sell price, transfer the remaining amount to the swap contract
        uint256 priceDiff;
        if (maximumBuyPrice > minimumSellPrice) {
            priceDiff = maximumBuyPrice - minimumSellPrice;
            IERC20(sellPool.getToken()).safeTransferFrom(
                msg.sender,
                address(this),
                priceDiff
            );
        }

        // Buy the NFTs
        uint256 buyPrice = buyPool.buy(msg.sender, buyNftIds, maximumBuyPrice);

        // If the price difference + sell price is greater than the buy price, return the difference to the user
        if (sellPrice + priceDiff > buyPrice) {
            IERC20(sellPool.getToken()).safeTransfer(
                msg.sender,
                sellPrice + priceDiff - buyPrice
            );
            change = sellPrice + priceDiff - buyPrice;
        }
    }

    /// @notice Approves a trading pool to spend an unlimited amount of tokens on behalf of this contract
    /// @param token The address of the token to approve
    /// @param tradingPool The address of the trading pool to approve
    function approveTradingPool(address token, address tradingPool) external {
        require(
            msg.sender == _addressProvider.getTradingPoolFactory(),
            "SR:ATP:NOT_FACTORY"
        );
        IERC20(token).safeApprove(tradingPool, type(uint256).max);
    }
}
