//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;

interface IMarket {
    event Deposit(address indexed user, address indexed asset, uint256 amount);

    event Withdraw(address indexed user, address indexed asset, uint256 amount);

    event Borrow(
        address indexed user,
        address indexed asset,
        address indexed nftAddress,
        uint256 nftTokenID,
        uint256 amount
    );

    event Repay(address indexed user, uint256 loanId);

    event Liquidate(address indexed user, uint256 loanId);

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
