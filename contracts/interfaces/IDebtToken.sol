//SPDX-License-Identifier: Unlicense
pragma solidity 0.8.19;

interface IDebtToken {
    event Mint(address to, uint256 loanId);

    function mint(address to, uint256 loanId) external;

    event Burn(uint256 loanId);

    function burn(uint256 loanId) external;
}
