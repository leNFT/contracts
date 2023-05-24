//SPDX-License-Identifier: Unlicense
pragma solidity 0.8.19;

interface IBribes {
    event DepositBribe(
        address indexed briber,
        address indexed token,
        address indexed gauge,
        uint256 amount
    );
    event WithdrawBribe(
        address indexed receiver,
        address indexed token,
        address indexed gauge,
        uint256 amount
    );

    event SalvageBribes(
        address indexed token,
        address indexed gauge,
        uint256 indexed epoch,
        uint256 amount
    );

    event ClaimBribes(
        address indexed receiver,
        address indexed token,
        address indexed gauge,
        uint256 tokenId,
        uint256 amount
    );

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
