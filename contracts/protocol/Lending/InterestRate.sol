// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.8.19;

import {IInterestRate} from "../../interfaces/IInterestRate.sol";
import {ConfigTypes} from "../../libraries/types/ConfigTypes.sol";
import {PercentageMath} from "../../libraries/utils/PercentageMath.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {SafeCast} from "../../libraries/utils/SafeCast.sol";

/// @title InterestRate
/// @author leNFT
/// @notice A contract for calculating the borrow rate based on the utilization rate
/// @dev This contract implements the IInterestRate interface
/// @dev The borrow rate is calculated based on a utilization rate between 0 and 100%
/// @dev The optimal utilization rate is the target utilization rate where the borrow rate is equal to the base rate plus the low slope
/// @dev Above the optimal utilization rate, the borrow rate is linearly increased based on the high slope
/// @dev Below the optimal utilization rate, the borrow rate is linearly increased based on the low slope
/// @dev Utilization rate is defined as the ratio of total debt to total liquidity in the system
/// @dev The calculation of the utilization rate is done by the internal _calculateUtilizationRate function
contract InterestRate is IInterestRate, Ownable {
    mapping(address => bool) private _isSupported;
    mapping(address => ConfigTypes.InterestRateConfig)
        private _interestRateConfigs;

    modifier onlySupported(address token) {
        _requireOnlySupported(token);
        _;
    }

    /// @notice Sets the interest rate parameters for a token
    /// @param token The address of the token
    /// @param optimalUtilizationRate The optimal utilization rate for the market (10000 = 100%)
    /// @param baseBorrowRate The market's base borrow rate (10000 = 100%)
    /// @param lowSlope The slope of the interest rate model when utilization rate is below the optimal utilization rate (10000 = 100%)
    /// @param highSlope The slope of the interest rate model when utilization rate is above the optimal utilization rate (10000 = 100%)
    function addToken(
        address token,
        uint256 optimalUtilizationRate,
        uint256 baseBorrowRate,
        uint256 lowSlope,
        uint256 highSlope
    ) external onlyOwner {
        require(_isSupported[token] == false, "IR:AT:TOKEN_ALREADY_SUPPORTED");
        _isSupported[token] = true;
        setInterestRateConfig(
            token,
            optimalUtilizationRate,
            baseBorrowRate,
            lowSlope,
            highSlope
        );

        emit TokenAdded(
            token,
            optimalUtilizationRate,
            baseBorrowRate,
            lowSlope,
            highSlope
        );
    }

    /// @notice Removes support for a token
    /// @param token The address of the token
    function removeToken(
        address token
    ) external onlySupported(token) onlyOwner {
        delete _isSupported[token];
        delete _interestRateConfigs[token];

        emit TokenRemoved(token);
    }

    /// @notice Gets whether a token is supported
    /// @param token The address of the token
    /// @return Whether the token is supported
    function isTokenSupported(address token) external view returns (bool) {
        return _isSupported[token];
    }

    /// @notice Gets the interest rate parameters for a token
    /// @param token The address of the token
    /// @return The interest rate parameters
    function getInterestRateConfig(
        address token
    )
        external
        view
        onlySupported(token)
        returns (ConfigTypes.InterestRateConfig memory)
    {
        return _interestRateConfigs[token];
    }

    /// @notice Calculates the borrow rate based on the utilization rate
    /// @param token The address of the token
    /// @param assets The total assets
    /// @param debt The total debt
    /// @return The borrow rate
    function calculateBorrowRate(
        address token,
        uint256 assets,
        uint256 debt
    ) external view override onlySupported(token) returns (uint256) {
        uint256 utilizationRate = _calculateUtilizationRate(assets, debt);

        if (
            utilizationRate < _interestRateConfigs[token].optimalUtilizationRate
        ) {
            return
                _interestRateConfigs[token].baseBorrowRate +
                PercentageMath.percentMul(
                    utilizationRate,
                    _interestRateConfigs[token].lowSlope
                );
        } else {
            return
                _getOptimalBorrowRate(_interestRateConfigs[token]) +
                PercentageMath.percentMul(
                    utilizationRate -
                        _interestRateConfigs[token].optimalUtilizationRate,
                    _interestRateConfigs[token].highSlope
                );
        }
    }

    function getOptimalBorrowRate(
        address token
    ) external view onlySupported(token) returns (uint256) {
        return _getOptimalBorrowRate(_interestRateConfigs[token]);
    }

    /// @notice Calculates the utilization rate based on the assets and debt
    /// @param assets The total assets
    /// @param debt The total debt
    /// @return The utilization rate
    function calculateUtilizationRate(
        address token,
        uint256 assets,
        uint256 debt
    ) external view override onlySupported(token) returns (uint256) {
        return _calculateUtilizationRate(assets, debt);
    }

    /// @notice Sets the interest rate parameters for a token
    /// @param token The address of the token
    /// @param optimalUtilizationRate The optimal utilization rate for the market (10000 = 100%)
    /// @param baseBorrowRate The market's base borrow rate (10000 = 100%)
    /// @param lowSlope The slope of the interest rate model when utilization rate is below the optimal utilization rate (10000 = 100%)
    /// @param highSlope The slope of the interest rate model when utilization rate is above the optimal utilization rate (10000 = 100%)
    function setInterestRateConfig(
        address token,
        uint256 optimalUtilizationRate,
        uint256 baseBorrowRate,
        uint256 lowSlope,
        uint256 highSlope
    ) public onlySupported(token) onlyOwner {
        uint64 optimalBorrowRate = SafeCast.toUint64(
            PercentageMath.percentMul(optimalUtilizationRate, lowSlope) +
                baseBorrowRate
        );

        _interestRateConfigs[token] = ConfigTypes.InterestRateConfig({
            optimalUtilizationRate: SafeCast.toUint64(optimalUtilizationRate),
            baseBorrowRate: SafeCast.toUint64(baseBorrowRate),
            lowSlope: SafeCast.toUint64(lowSlope),
            highSlope: SafeCast.toUint64(highSlope),
            optimalBorrowRate: optimalBorrowRate
        });

        emit InterestRateConfigSet(
            token,
            optimalUtilizationRate,
            baseBorrowRate,
            lowSlope,
            highSlope,
            optimalBorrowRate
        );
    }

    /// @notice Internal function to get the optimal borrow rate
    /// @param interestRateConfig The interest rate parameters
    /// @return The optimal borrow rate
    function _getOptimalBorrowRate(
        ConfigTypes.InterestRateConfig memory interestRateConfig
    ) internal pure returns (uint256) {
        return interestRateConfig.optimalBorrowRate;
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

    function _requireOnlySupported(address token) internal view {
        require(_isSupported[token], "IR:TOKEN_NOT_SUPPORTED");
    }
}
