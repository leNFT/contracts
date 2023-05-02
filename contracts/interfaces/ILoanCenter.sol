//SPDX-License-Identifier: Unlicense
pragma solidity 0.8.19;

import {DataTypes} from "../libraries/types/DataTypes.sol";
import {Trustus} from "../protocol/Trustus/Trustus.sol";

interface ILoanCenter {
    function createLoan(
        address borrower,
        address lendingPool,
        uint256 amount,
        uint256 maxLTV,
        uint256 boost,
        uint256 genesisNFTId,
        address nftAddress,
        uint256[] memory nftTokenIds,
        uint256 borrowRate
    ) external returns (uint256);

    function getLoan(
        uint256 loanId
    ) external view returns (DataTypes.LoanData memory);

    function repayLoan(uint256 loanId) external;

    function liquidateLoan(uint256 loanId) external;

    function auctionLoan(uint256 loanId, address user, uint256 bid) external;

    function updateLoanAuctionBid(
        uint256 loanId,
        address user,
        uint256 bid
    ) external;

    function activateLoan(uint256 loanId) external;

    function getLoansCount() external view returns (uint256);

    function getActiveLoansCount(
        address user,
        address collection
    ) external view returns (uint256);

    function getNFTLoanId(
        address nftAddress,
        uint256 nftTokenID
    ) external view returns (uint256);

    function getLoanLendingPool(uint256 loanId) external view returns (address);

    function getLoanMaxETHCollateral(
        uint256 loanId,
        bytes32 request,
        Trustus.TrustusPacket calldata packet
    ) external view returns (uint256);

    function getLoanDebt(uint256 loanId) external view returns (uint256);

    function getLoanInterest(uint256 loanId) external view returns (uint256);

    function getLoanTokenIds(
        uint256 loanId
    ) external view returns (uint256[] memory);

    function getLoanTokenAddress(
        uint256 loanId
    ) external view returns (address);

    function updateLoanDebtTimestamp(
        uint256 loanId,
        uint256 newDebtTimestamp
    ) external;

    function updateLoanAmount(uint256 loanId, uint256 newAmount) external;

    function getCollectionMaxCollaterization(
        address collection
    ) external view returns (uint256);

    function changeCollectionMaxCollaterization(
        address collection,
        uint256 maxCollaterization
    ) external;

    function approveNFTCollection(address collection) external;
}
