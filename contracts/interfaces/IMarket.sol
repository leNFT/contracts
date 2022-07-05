//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;

interface IMarket {
    function deposit(address asset, uint256 amount) external;

    function withdraw(address asset, uint256 amount) external;

    function borrow(
        address asset,
        uint256 amount,
        address nftAddress,
        uint256 nftTokenID
    ) external;

    function repay(uint256 loanId) external;

    function liquidate(uint256 loanId) external;
}
