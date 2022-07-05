// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.8.15;

import {IInterestRate} from "../interfaces/IInterestRate.sol";
import {PercentageMath} from "../libraries/math/PercentageMath.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

contract InterestRate is Initializable, IInterestRate {
    uint256 internal _optimalUtilization;
    uint256 internal _optimalBorrowRate;
    uint256 internal _baseBorrowRate;
    uint256 internal _lowSlope;
    uint256 internal _highSlope;
    uint256 internal _optimalInterest;

    constructor(
        uint256 optimalUtilization,
        uint256 baseBorrowRate,
        uint256 lowSlope,
        uint256 highSlope
    ) {
        _optimalUtilization = optimalUtilization;
        _baseBorrowRate = baseBorrowRate;
        _lowSlope = lowSlope;
        _highSlope = highSlope;

        _optimalBorrowRate =
            PercentageMath.percentMul(_optimalUtilization, _lowSlope) +
            _baseBorrowRate;
    }

    function calculateBorrowRate(uint256 assets, uint256 debt)
        external
        view
        override
        returns (uint256)
    {
        uint256 utilizationRate = _calculateUtilizationRate(assets, debt);

        uint256 borrowRate;

        if (utilizationRate < _optimalUtilization) {
            borrowRate =
                PercentageMath.percentMul(utilizationRate, _lowSlope) +
                _baseBorrowRate;
        } else {
            borrowRate =
                _optimalBorrowRate +
                PercentageMath.percentMul(
                    utilizationRate - _optimalUtilization,
                    _highSlope
                );
        }

        return borrowRate;
    }

    function getOptimalInterest() external view returns (uint256) {
        return _optimalInterest;
    }

    function getOptimalBorrowRate() external view returns (uint256) {
        return _optimalBorrowRate;
    }

    function getLowSlope() external view returns (uint256) {
        return _lowSlope;
    }

    function getHighSlope() external view returns (uint256) {
        return _highSlope;
    }

    function calculateUtilizationRate(uint256 assets, uint256 debt)
        external
        pure
        returns (uint256)
    {
        return _calculateUtilizationRate(assets, debt);
    }

    function _calculateUtilizationRate(uint256 assets, uint256 debt)
        internal
        pure
        returns (uint256)
    {
        uint256 utilizationRate;

        if ((assets + debt) == 0) {
            utilizationRate = 0;
        } else {
            utilizationRate =
                (PercentageMath.PERCENTAGE_FACTOR * debt) /
                (assets + debt);
        }
        return utilizationRate;
    }
}
