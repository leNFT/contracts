//SPDX-License-Identifier: Unlicense
pragma solidity 0.8.19;

interface IInterestRate {
    function calculateBorrowRate(
        uint256 assets,
        uint256 debt
    ) external view returns (uint256);

    function calculateUtilizationRate(
        uint256 assets,
        uint256 debt
    ) external pure returns (uint256);
}
