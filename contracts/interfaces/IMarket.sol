//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;

import {Trustus} from "../protocol/Trustus.sol";

interface IMarket {
    event Deposit(
        address indexed user,
        address indexed reserve,
        uint256 amount
    );

    event Withdraw(
        address indexed user,
        address indexed reserve,
        uint256 amount
    );

    event Borrow(
        address indexed user,
        address indexed asset,
        address indexed nftAddress,
        uint256 nftTokenID,
        uint256 amount
    );

    event Repay(address indexed user, uint256 indexed loanId);

    event Liquidate(address indexed user, uint256 indexed loanId);

    event CreateReserve(address indexed reserve);

    event SetReserve(
        address indexed collection,
        address indexed asset,
        address indexed reserve
    );

    function deposit(address reserve, uint256 amount) external;

    function depositETH(address collection) external payable;

    function withdraw(address reserve, uint256 amount) external;

    function withdrawETH(address reserve, uint256 amount) external;

    function borrow(
        address asset,
        uint256 amount,
        address nftAddress,
        uint256 nftTokenID,
        uint256 genesisNFTId,
        bytes32 request,
        Trustus.TrustusPacket calldata packet
    ) external;

    function borrowETH(
        uint256 amount,
        address nftAddress,
        uint256 nftTokenID,
        uint256 genesisNFTId,
        bytes32 request,
        Trustus.TrustusPacket calldata packet
    ) external;

    function repay(uint256 loanId, uint256 amount) external;

    function repayETH(uint256 loanId) external payable;

    function liquidate(
        uint256 loanId,
        bytes32 request,
        Trustus.TrustusPacket calldata packet
    ) external;

    function getReserve(address collection, address asset)
        external
        view
        returns (address);
}
