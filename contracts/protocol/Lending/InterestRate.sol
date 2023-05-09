// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.8.19;

import {IInterestRate} from "../../interfaces/IInterestRate.sol";
import {ConfigTypes} from "../../libraries/types/ConfigTypes.sol";
import {PercentageMath} from "../../libraries/math/PercentageMath.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/// @title InterestRate
/// @notice A contract for calculating the borrow rate based on the utilization rate
/// @dev This contract implements the IInterestRate interface
/// @dev The borrow rate is calculated based on a utilization rate between 0 and 100%
/// @dev The optimal utilization rate is the target utilization rate where the borrow rate is equal to the base rate plus the low slope
/// @dev Above the optimal utilization rate, the borrow rate is linearly increased based on the high slope
/// @dev Below the optimal utilization rate, the borrow rate is linearly increased based on the low slope
/// @dev Utilization rate is defined as the ratio of total debt to total assets in the system
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
    /// @param interestRateConfig The interest rate parameters
    function addToken(
        address token,
        ConfigTypes.InterestRateConfig memory interestRateConfig
    ) external onlyOwner {
        _isSupported[token] = true;
        _interestRateConfigs[token] = interestRateConfig;
    }

    /// @notice Removes support for a token
    /// @param token The address of the token
    function removeToken(address token) external onlyOwner {
        delete _isSupported[token];
        delete _interestRateConfigs[token];
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
                getOptimalBorrowRate(token) +
                PercentageMath.percentMul(
                    utilizationRate -
                        _interestRateConfigs[token].optimalUtilizationRate,
                    _interestRateConfigs[token].highSlope
                );
        }
    }

    /// @notice Gets the optimal borrow rate
    /// @return The optimal borrow rate
    function getOptimalBorrowRate(
        address token
    ) public view onlySupported(token) returns (uint256) {
        return
            PercentageMath.percentMul(
                _interestRateConfigs[token].optimalUtilizationRate,
                _interestRateConfigs[token].lowSlope
            ) + _interestRateConfigs[token].baseBorrowRate;
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
