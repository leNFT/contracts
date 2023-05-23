//SPDX-License-Identifier: Unlicense
pragma solidity 0.8.19;

library ConfigTypes {
    /// @param maxLiquidatorDiscount The maximum discount liquidators can get when liquidating a certain collateral with a certain price
    /// @param auctioneerFee The fee borrowers have to pay to the auctioneer when repaying a loan after liquidation
    /// @param liquidationFee The fee liquidators have to pay to the protocol when liquidating a loan
    /// @param maxUtilizationRate The maximum utilization rate of the pool for withdraws
    struct LendingPoolConfig {
        uint256 maxLiquidatorDiscount;
        uint256 auctioneerFee;
        uint256 liquidationFee;
        uint256 maxUtilizationRate;
    }

    /// @param optimalUtilization The optimal utilization rate for the market, expressed in ray
    /// @param baseBorrowRate The market's base borrow rate, expressed in ray
    /// @param lowSlope The slope of the interest rate model when utilization rate is below the optimal utilization rate, expressed in ray
    /// @param highSlope The slope of the interest rate model when utilization rate is above the opt
    struct InterestRateConfig {
        uint256 optimalUtilizationRate;
        uint256 baseBorrowRate;
        uint256 lowSlope;
        uint256 highSlope;
    }
}
