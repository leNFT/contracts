//SPDX-License-Identifier: Unlicense
pragma solidity 0.8.19;

interface IBribes {
    function depositBribe(
        address briber,
        address token,
        address gauge,
        uint256 amount
    ) external;

    function withdrawBribe(
        address receiver,
        address token,
        address gauge,
        uint256 amount
    ) external;
}
