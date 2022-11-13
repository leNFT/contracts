//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;

import {Trustus} from "../protocol/Trustus/Trustus.sol";

interface IMarket {
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

    function withdraw(address reserve, uint256 amount) external;

    function borrow(
        address initiator,
        address depositor,
        address asset,
        uint256 amount,
        address nftAddress,
        uint256 nftTokenID,
        uint256 genesisNFTId,
        bytes32 request,
        Trustus.TrustusPacket calldata packet
    ) external;

    function repay(
        address initiator,
        uint256 loanId,
        uint256 amount
    ) external;

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
