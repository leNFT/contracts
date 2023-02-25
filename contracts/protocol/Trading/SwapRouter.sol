// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.8.17;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Context} from "@openzeppelin/contracts/utils/Context.sol";
import {IAddressesProvider} from "../../interfaces/IAddressesProvider.sol";
import {ITradingPool} from "../../interfaces/ITradingPool.sol";
import {ISwapRouter} from "../../interfaces/ISwapRouter.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "hardhat/console.sol";

/// @title SwapRouter Contract
/// @author leNFT
/// @notice This contract is responsible for swapping between assets in different pools
contract SwapRouter is ISwapRouter, Ownable, ReentrancyGuard {
    IAddressesProvider private _addressProvider;

    using SafeERC20 for IERC20;

    /// @notice Initialize the market
    /// @param addressesProvider The address of the AddressesProvider contract
    constructor(IAddressesProvider addressesProvider) {
        _addressProvider = addressesProvider;
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
    /// @return The amount of tokens returned to the user
    function swap(
        ITradingPool buyPool,
        ITradingPool sellPool,
        uint256[] calldata buyNftIds,
        uint256 maximumBuyPrice,
        uint256[] calldata sellNftIds,
        uint256[] calldata sellLps,
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

        // If the buy price is greater than the sell price, transfer the remaining amount to the swap contract
        uint256 priceDiff = 0;
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
            uint256 returnedAmount = sellPrice + priceDiff - buyPrice;
            IERC20(sellPool.getToken()).safeTransfer(
                msg.sender,
                returnedAmount
            );
            return returnedAmount;
        }

        return 0;
    }

    /// @notice Approves a trading pool to spend an unlimited amount of tokens on behalf of this contract
    /// @param token The address of the token to approve
    ///@param tradingPool The address of the trading pool to approve
    function approveTradingPool(address token, address tradingPool) external {
        require(
            msg.sender == _addressProvider.getTradingPoolFactory(),
            "Only trading pool factory can approve trading pool."
        );
        IERC20(token).safeApprove(tradingPool, type(uint256).max);
    }
}
