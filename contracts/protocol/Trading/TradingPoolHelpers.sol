// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.8.19;

import {DataTypes} from "../../libraries/types/DataTypes.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {ITradingPool} from "../../interfaces/ITradingPool.sol";
import {IPricingCurve} from "../../interfaces/IPricingCurve.sol";
import {PercentageMath} from "../../libraries/utils/PercentageMath.sol";
import {IAddressProvider} from "../../interfaces/IAddressProvider.sol";
import {ITradingPoolFactory} from "../../interfaces/ITradingPoolFactory.sol";

/// @title TradingPoolHelpers Contract
/// @notice Helper functions for the TradingPool contract
contract TradingPoolHelpers {
    // Address provider state variable
    IAddressProvider private immutable _addressProvider;

    constructor(address addressProvider) {
        _addressProvider = IAddressProvider(addressProvider);
    }

    /// @notice Simulates a trading pool buy call
    /// @param tradingPool The address of the trading pool
    /// @param nftIds The array of NFT IDs to buy
    /// @return finalPrice The final price quote for the NFTs
    function simulateBuy(
        address tradingPool,
        uint256[] calldata nftIds
    ) external view returns (uint256 finalPrice) {
        require(nftIds.length > 0, "TP:B:NFTS_0");

        // Create an array of liquidity pairs to keep track of the prices & token amounts
        DataTypes.LiquidityPair[]
            memory liquidityPairsData = new DataTypes.LiquidityPair[](
                nftIds.length
            );
        // Create an array of liquidity pair IDs to keep track of the liquidity pairs
        uint256[] memory lpIds = new uint256[](nftIds.length);

        uint256 lpIndex;
        uint256 lpCount;
        DataTypes.LiquidityPair memory lp;
        bool lpFound;
        for (uint i = 0; i < nftIds.length; i++) {
            // Check for repeated NFTs (needed when simulation but would fail in buy)
            for (uint j = i + 1; j < nftIds.length; j++) {
                require(nftIds[i] != nftIds[j], "TP:B:REPEATED_NFT");
            }

            // Check if the pool contract owns the NFT
            require(
                IERC721(ITradingPool(tradingPool).getNFT()).ownerOf(
                    nftIds[i]
                ) == tradingPool,
                "TP:B:NOT_OWNER"
            );
            lpIndex = ITradingPool(tradingPool).nftToLp(nftIds[i]);

            // Add liquidity pair to array if not already there
            for (uint j = 0; j < lpCount; j++) {
                if (lpIds[j] == lpIndex) {
                    lpFound = true;
                    break;
                }
            }

            // If it reaches the end of the array, it means it didn't find the liquidity pair
            if (!lpFound) {
                lpIds[lpCount] = lpIndex;
                lp = ITradingPool(tradingPool).getLP(lpIndex);
                // Can't buy from buy LP
                require(lp.lpType != DataTypes.LPType.Buy, "TP:B:IS_BUY_LP");
                liquidityPairsData[lpCount] = lp;
                lpCount++;
                delete lpFound;
            }
        }

        // scope vars to Avoid stack too deep errors
        {
            // Simulate buying the NFTs
            uint256 fee;
            uint256 lpDataIndex;
            uint256 protocolFee;
            uint256 protocolFeePercentage = ITradingPoolFactory(
                _addressProvider.getTradingPoolFactory()
            ).getProtocolFeePercentage();
            for (uint i = 0; i < nftIds.length; i++) {
                // Find the liquidity pair in the array
                lpIndex = ITradingPool(tradingPool).nftToLp(nftIds[i]);
                for (uint j = 0; j < lpCount; j++) {
                    if (lpIds[j] == lpIndex) {
                        lpDataIndex = j;
                        lp = liquidityPairsData[lpDataIndex];
                        break;
                    }
                }

                fee = PercentageMath.percentMul(lp.spotPrice, lp.fee);
                protocolFee = PercentageMath.percentMul(
                    fee,
                    protocolFeePercentage
                );

                liquidityPairsData[lpDataIndex].tokenAmount += (lp.spotPrice +
                    fee -
                    protocolFee);

                // Increase total price and fee sum
                finalPrice += (lp.spotPrice + fee);

                // Update liquidity pair price
                if (lp.lpType != DataTypes.LPType.TradeDown) {
                    liquidityPairsData[lpDataIndex].spotPrice = IPricingCurve(
                        lp.curve
                    ).priceAfterBuy(lp.spotPrice, lp.delta, lp.fee);
                }
            }
        }
    }

    /// @notice Simulates a trading pool sell call
    /// @param tradingPool The address of the trading pool
    /// @param nftIds The array of NFT IDs to sell
    /// @param liquidityPairs The array of liquidity pair IDs to sell
    /// @return finalPrice The final price quote for the sell operation
    function simulateSell(
        address tradingPool,
        uint256[] calldata nftIds,
        uint256[] calldata liquidityPairs
    ) external view returns (uint256 finalPrice) {
        require(
            nftIds.length == liquidityPairs.length,
            "TPH:SS:NFT_LP_MISMATCH"
        );
        require(nftIds.length > 0, "TPH:SS:NFTS_0");

        uint256 lpIndex;
        uint256 lpCount;
        bool lpFound;
        DataTypes.LiquidityPair memory lp;

        // Create an array of liquidity pairs to keep track of the prices & token amounts
        DataTypes.LiquidityPair[]
            memory liquidityPairsData = new DataTypes.LiquidityPair[](
                nftIds.length
            );
        // Create an array of liquidity pair IDs to keep track of the liquidity pairs
        uint256[] memory lpIds = new uint256[](nftIds.length);

        // Fill the array with the prices of the liquidity pairs
        for (uint i = 0; i < liquidityPairs.length; i++) {
            // Check for repeated NFTs (needed when simulation but would fail in sell)
            for (uint j = i + 1; j < nftIds.length; j++) {
                require(nftIds[i] != nftIds[j], "TP:B:REPEATED_NFT");
            }

            lpIndex = liquidityPairs[i];
            require(
                IERC721(tradingPool).ownerOf(lpIndex) != address(0),
                "TPH:SS:LP_NOT_FOUND"
            );

            // Add liquidity pair to array if not already there
            for (uint j = 0; j < lpCount; j++) {
                if (lpIds[j] == lpIndex) {
                    lpFound = true;
                    break;
                }
            }

            // If it reaches the end of the array, it means it didn't find the liquidity pair
            if (!lpFound) {
                lpIds[lpCount] = lpIndex;
                lp = ITradingPool(tradingPool).getLP(lpIndex);
                // Can't sell to sell LP
                require(lp.lpType != DataTypes.LPType.Sell, "TP:S:IS_SELL_LP");
                liquidityPairsData[lpCount] = lp;
                lpCount++;
                delete lpFound;
            }
        }

        // scope to avoid stack too deep errors
        {
            // Simulate selling the NFTs
            uint256 fee;
            uint256 protocolFee;
            uint256 lpDataIndex;
            uint256 protocolFeePercentage = ITradingPoolFactory(
                _addressProvider.getTradingPoolFactory()
            ).getProtocolFeePercentage();
            for (uint i = 0; i < nftIds.length; i++) {
                // Find the liquidity pair in the array
                lpIndex = liquidityPairs[i];
                for (uint j = 0; j < lpCount; j++) {
                    if (lpIds[j] == lpIndex) {
                        lpDataIndex = j;
                        lp = liquidityPairsData[lpDataIndex];
                        break;
                    }
                }

                fee = PercentageMath.percentMul(lp.spotPrice, lp.fee);
                protocolFee = PercentageMath.percentMul(
                    fee,
                    protocolFeePercentage
                );

                require(
                    lp.tokenAmount >= lp.spotPrice - fee + protocolFee,
                    "TP:S:INSUFFICIENT_TOKENS_IN_LP"
                );
                liquidityPairsData[lpDataIndex].tokenAmount -= (lp.spotPrice -
                    fee +
                    protocolFee);

                // Update total price quote and fee sum
                finalPrice += (lp.spotPrice - fee);

                // Update liquidity pair price
                if (lp.lpType != DataTypes.LPType.TradeUp) {
                    liquidityPairsData[lpDataIndex].spotPrice = IPricingCurve(
                        lp.curve
                    ).priceAfterSell(lp.spotPrice, lp.delta, lp.fee);
                }
            }
        }
    }

    /// @notice Returns the best liquidity pairs to sell the NFTs into
    /// @param pool The address of the trading pool
    /// @param amount The amount of tokens the user wants to sell
    /// @return sellLiquidityPairs The array of liquidity pairs to sell into
    function getSellLiquidityPairs(
        address pool,
        uint256 amount
    ) external view returns (uint256[] memory sellLiquidityPairs) {
        uint256 lpCount = ITradingPool(pool).getLpCount();
        uint256[] memory validLiquidityPairs = new uint256[](lpCount);
        uint256 validLiquidityPairsCount = 0;

        // Loop through all liquidity pairs
        uint256 fee;
        uint256 protocolFee;
        uint256 protocolFeePercentage = ITradingPoolFactory(
            _addressProvider.getTradingPoolFactory()
        ).getProtocolFeePercentage();
        DataTypes.LiquidityPair memory lp;
        // Go through all liquidity pairs
        for (uint i = 0; i < lpCount; i++) {
            lp = ITradingPool(pool).getLP(i);
            // Check if the lp still exists and is not a sell LP
            if (
                IERC721(pool).ownerOf(i) != address(0) &&
                lp.lpType != DataTypes.LPType.Sell
            ) {
                fee = PercentageMath.percentMul(lp.spotPrice, lp.fee);
                protocolFee = PercentageMath.percentMul(
                    fee,
                    protocolFeePercentage
                );

                // Check if the amount is enough to buy the asset
                if (lp.tokenAmount >= lp.spotPrice - fee + protocolFee) {
                    validLiquidityPairs[validLiquidityPairsCount] = i;
                    validLiquidityPairsCount++;
                }
            }
        }

        // Find the best liquidity pairs to sell into (highest price after fees)
        sellLiquidityPairs = new uint256[](amount);
        uint256[] memory priceSellLiquidityPairs = new uint256[](amount);
        for (uint i = 0; i < validLiquidityPairsCount; i++) {
            lp = ITradingPool(pool).getLP(validLiquidityPairs[i]);
            // Check if the current liquidity pair is better than the worst one in the array
            uint256 priceAfterFees = (lp.spotPrice *
                (PercentageMath.PERCENTAGE_FACTOR - lp.fee)) /
                PercentageMath.PERCENTAGE_FACTOR;

            if (priceAfterFees > priceSellLiquidityPairs[amount - 1]) {
                // Replace the worst liquidity pair with the current one
                sellLiquidityPairs[amount - 1] = validLiquidityPairs[i];
                priceSellLiquidityPairs[amount - 1] = priceAfterFees;

                // Sort the array
                for (uint j = amount - 1; j > 0; j--) {
                    if (
                        priceSellLiquidityPairs[j] >
                        priceSellLiquidityPairs[j - 1]
                    ) {
                        uint256 temp = sellLiquidityPairs[j];
                        sellLiquidityPairs[j] = sellLiquidityPairs[j - 1];
                        sellLiquidityPairs[j - 1] = temp;
                        uint256 temp2 = priceSellLiquidityPairs[j];
                        priceSellLiquidityPairs[j] = priceSellLiquidityPairs[
                            j - 1
                        ];
                        priceSellLiquidityPairs[j - 1] = temp2;
                    } else {
                        break;
                    }
                }
            }
        }

        // Go through the best liquidity pairs to check if for multiple selling to the same LP
        uint256 nextSpotPrice;
        DataTypes.LiquidityPair[]
            memory sellLiquidityPairsData = new DataTypes.LiquidityPair[](
                amount
            );
        sellLiquidityPairsData[0] = ITradingPool(pool).getLP(
            sellLiquidityPairs[0]
        );
        for (uint x = 0; x < amount - 1; x++) {
            lp = sellLiquidityPairsData[x];
            nextSpotPrice = IPricingCurve(lp.curve).priceAfterSell(
                lp.spotPrice,
                lp.delta,
                lp.fee
            );
            fee = PercentageMath.percentMul(lp.spotPrice, lp.fee);
            protocolFee = PercentageMath.percentMul(fee, protocolFeePercentage);

            // Replace the worst liquidity pair with the current one
            if (
                nextSpotPrice - fee > priceSellLiquidityPairs[amount - 1] &&
                sellLiquidityPairsData[x].tokenAmount >=
                nextSpotPrice - fee + protocolFee
            ) {
                sellLiquidityPairs[amount - 1] = sellLiquidityPairs[x];
                priceSellLiquidityPairs[amount - 1] = nextSpotPrice - fee;
                sellLiquidityPairsData[amount - 1] = lp;
                // Update token amount and spot price for lp
                sellLiquidityPairsData[amount - 1]
                    .tokenAmount -= (nextSpotPrice - fee + protocolFee);
                sellLiquidityPairsData[amount - 1].spotPrice = nextSpotPrice;

                // Sort the array
                for (uint j = amount - 1; j > 0; j--) {
                    if (
                        priceSellLiquidityPairs[j] >
                        priceSellLiquidityPairs[j - 1]
                    ) {
                        uint256 temp = sellLiquidityPairs[j];
                        sellLiquidityPairs[j] = sellLiquidityPairs[j - 1];
                        sellLiquidityPairs[j - 1] = temp;
                        uint256 temp2 = priceSellLiquidityPairs[j];
                        priceSellLiquidityPairs[j] = priceSellLiquidityPairs[
                            j - 1
                        ];
                        priceSellLiquidityPairs[j - 1] = temp2;
                        DataTypes.LiquidityPair
                            memory temp3 = sellLiquidityPairsData[j];
                        sellLiquidityPairsData[j] = sellLiquidityPairsData[
                            j - 1
                        ];
                        sellLiquidityPairsData[j - 1] = temp3;
                    } else {
                        break;
                    }
                }
            }
        }

        // Return the best liquidity pairs after pruning the ones at price 0
        uint256 finalSellLiquidityPairsCount = 0;
        for (uint i = 0; i < amount; i++) {
            if (priceSellLiquidityPairs[i] > 0) {
                finalSellLiquidityPairsCount++;
            } else {
                break;
            }
        }

        uint256[] memory finalSellLiquidityPairs = new uint256[](
            finalSellLiquidityPairsCount
        );
        for (uint i = 0; i < finalSellLiquidityPairsCount; i++) {
            finalSellLiquidityPairs[i] = sellLiquidityPairs[i];
        }

        return finalSellLiquidityPairs;
    }
}
