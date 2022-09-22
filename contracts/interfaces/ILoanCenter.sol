//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;

import {DataTypes} from "../libraries/types/DataTypes.sol";

interface ILoanCenter {
    function createLoan(
        address borrower,
        address reserve,
        uint256 amount,
        uint256 maxLTV,
        uint256 boost,
        address nftAddress,
        uint256 nftTokenID,
        uint256 borrowRate
    ) external returns (uint256);

    function getLoan(uint256 loanId)
        external
        view
        returns (DataTypes.LoanData memory);

    function repayLoan(uint256 loanId) external;

    function liquidateLoan(uint256 loanId) external;

    function activateLoan(uint256 loanId) external;

    function getLoansCount() external view returns (uint256);

    function getUserCollectionActiveLoansCount(address user, address collection)
        external
        view
        returns (uint256);

    function getNFTLoanId(address nftAddress, uint256 nftTokenID)
        external
        view
        returns (uint256);

    function getLoanDebt(uint256 loanId) external view returns (uint256);

    function getLoanInterest(uint256 loanId) external view returns (uint256);

    function getLoanTokenId(uint256 loanId) external view returns (uint256);

    function getLoanTokenAddress(uint256 loanId)
        external
        view
        returns (address);

    function getLoanBoost(uint256 loanId) external view returns (uint256);
}
