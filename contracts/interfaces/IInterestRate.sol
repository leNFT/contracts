//SPDX-License-Identifier: Unlicense
pragma solidity 0.8.19;

interface IInterestRate {
    function calculateBorrowRate(
        address token,
        uint256 assets,
        uint256 debt
    ) external view returns (uint256);

    function calculateUtilizationRate(
        address token,
        uint256 assets,
        uint256 debt
    ) external view returns (uint256);

    function isTokenSupported(address token) external view returns (bool);
}
