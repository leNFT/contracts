//SPDX-License-Identifier: Unlicense
pragma solidity 0.8.17;

interface IWETH {
    function deposit() external payable;

    function withdraw(uint) external;

    function approve(address guy, uint wad) external returns (bool);
}
