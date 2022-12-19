//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;

import {Trustus} from "../protocol/Trustus/Trustus.sol";

interface ILendingMarket {
    event Borrow(
        address indexed user,
        address indexed asset,
        address indexed nftAddress,
        uint256 nftTokenID,
        uint256 amount
    );

    event Repay(address indexed user, uint256 indexed loanId);

    event Liquidate(address indexed user, uint256 indexed loanId);

    event CreateLendingPool(address indexed lendingPool);

    event SetLendingPool(
        address indexed collection,
        address indexed asset,
        address indexed lendingPool
    );

    function borrow(
        address onBehalfOf,
        address asset,
        uint256 amount,
        address nftAddress,
        uint256 nftTokenID,
        uint256 genesisNFTId,
        bytes32 request,
        Trustus.TrustusPacket calldata packet
    ) external;

    function repay(uint256 loanId, uint256 amount) external;

    function liquidate(
        uint256 loanId,
        bytes32 request,
        Trustus.TrustusPacket calldata packet
    ) external;

    function getLendingPool(
        address collection,
        address asset
    ) external view returns (address);
}