// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.8.19;

import {IInterestRate} from "../../interfaces/IInterestRate.sol";
import {PercentageMath} from "../../libraries/math/PercentageMath.sol";

/// @title InterestRate
/// @notice A contract for calculating the borrow rate based on the utilization rate
/// @dev This contract implements the IInterestRate interface
/// @dev The borrow rate is calculated based on a utilization rate between 0 and 100%
/// @dev The optimal utilization rate is the target utilization rate where the borrow rate is equal to the base rate plus the low slope
/// @dev Above the optimal utilization rate, the borrow rate is linearly increased based on the high slope
/// @dev Below the optimal utilization rate, the borrow rate is linearly increased based on the low slope
/// @dev Utilization rate is defined as the ratio of total debt to total assets in the system
/// @dev The calculation of the utilization rate is done by the internal _calculateUtilizationRate function
contract InterestRate is IInterestRate {
    uint256 public immutable OPTIMAL_UTILIZATION_RATE;
    uint256 internal immutable _baseBorrowRate;
    uint256 internal immutable _lowSlope;
    uint256 internal immutable _highSlope;

    /// @notice Constructor for the interest rate contract
    /// @param optimalUtilization The optimal utilization rate for the market, expressed in ray
    /// @param baseBorrowRate The market's base borrow rate, expressed in ray
    /// @param lowSlope The slope of the interest rate model when utilization rate is below the optimal utilization rate, expressed in ray
    /// @param highSlope The slope of the interest rate model when utilization rate is above the opt
    constructor(
        uint256 optimalUtilization,
        uint256 baseBorrowRate,
        uint256 lowSlope,
        uint256 highSlope
    ) {
        OPTIMAL_UTILIZATION_RATE = optimalUtilization;
        _baseBorrowRate = baseBorrowRate;
        _lowSlope = lowSlope;
        _highSlope = highSlope;
    }

    /// @notice Calculates the borrow rate based on the utilization rate
    /// @param assets The total assets
    /// @param debt The total debt
    /// @return The borrow rate
    function calculateBorrowRate(
        uint256 assets,
        uint256 debt
    ) external view override returns (uint256) {
        uint256 utilizationRate = _calculateUtilizationRate(assets, debt);

        if (utilizationRate < OPTIMAL_UTILIZATION_RATE) {
            return
                _baseBorrowRate +
                PercentageMath.percentMul(utilizationRate, _lowSlope);
        } else {
            return
                getOptimalBorrowRate() +
                PercentageMath.percentMul(
                    utilizationRate - OPTIMAL_UTILIZATION_RATE,
                    _highSlope
                );
        }
    }

    /// @notice Gets the optimal borrow rate
    /// @return The optimal borrow rate
    function getOptimalBorrowRate() public view returns (uint256) {
        return
            PercentageMath.percentMul(OPTIMAL_UTILIZATION_RATE, _lowSlope) +
            _baseBorrowRate;
    }

    /// @notice Calculates the utilization rate based on the assets and debt
    /// @param assets The total assets
    /// @param debt The total debt
    /// @return The utilization rate
    function calculateUtilizationRate(
        uint256 assets,
        uint256 debt
    ) external pure override returns (uint256) {
        return _calculateUtilizationRate(assets, debt);
    }

    /// @notice Internal function to calculate the utilization rate based on the assets and debt
    /// @param assets The total assets
    /// @param debt The total debt
    function _calculateUtilizationRate(
        uint256 assets,
        uint256 debt
    ) internal pure returns (uint256) {
        if ((assets + debt) == 0) {
            return 0;
        } else {
            return (PercentageMath.PERCENTAGE_FACTOR * debt) / (assets + debt);
        }
    }
}
