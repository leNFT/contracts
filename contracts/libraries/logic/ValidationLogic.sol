// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.8.15;

import {DataTypes} from "../types/DataTypes.sol";
import {PercentageMath} from "../math/PercentageMath.sol";
import {INFTOracle} from "../../interfaces/INFTOracle.sol";
import {IInterestRate} from "../../interfaces/IInterestRate.sol";
import {IMarketAddressesProvider} from "../../interfaces/IMarketAddressesProvider.sol";
import {ILoanCenter} from "../../interfaces/ILoanCenter.sol";
import {IReserve} from "../../interfaces/IReserve.sol";
import {INativeTokenVault} from "../../interfaces/INativeTokenVault.sol";
import {LoanLogic} from "./LoanLogic.sol";
import {RemoveVoteRequestLogic} from "./RemoveVoteRequestLogic.sol";
import {IERC721Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC721/IERC721Upgradeable.sol";
import {IERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "hardhat/console.sol";

library ValidationLogic {
    uint256 internal constant ONE_DAY = 86400;
    uint256 internal constant ONE_WEEK = 86400 * 7;
    uint256 internal constant UNVOTE_WINDOW = 86400 * 2;
    using LoanLogic for DataTypes.LoanData;
    using RemoveVoteRequestLogic for DataTypes.RemoveVoteRequest;

    function validateDeposit(address asset, uint256 amount) external view {
        // Get balance of the user trying the deposit
        uint256 balance = IERC20Upgradeable(asset).balanceOf(msg.sender);

        require(amount <= balance, "Balance is lower than deposited amount");
    }

    function validateWithdrawal(
        IMarketAddressesProvider addressesProvider,
        address reserveAddress,
        uint256 amount
    ) external view {
        // Check if the utilization rate doesn't go above maximum
        IReserve reserve = IReserve(reserveAddress);

        uint256 maximumUtilizationRate = reserve.getMaximumUtilizationRate();
        uint256 debt = reserve.getDebt();
        uint256 underlyingBalance = reserve.getUnderlyingBalance();
        uint256 updatedUtilizationRate = IInterestRate(
            addressesProvider.getInterestRate()
        ).calculateUtilizationRate(underlyingBalance - amount, debt);

        require(
            updatedUtilizationRate <= maximumUtilizationRate,
            "Reserve utilization rate too high"
        );

        // Check if the user has enough reserve balance for withdrawal
        require(
            amount <= reserve.getMaximumWithdrawalAmount(msg.sender),
            "Amount too high"
        );
    }

    // Check if borrowing conditions are valid
    function validateBorrow(
        IMarketAddressesProvider addressesProvider,
        address reserveAdress,
        uint256 amount,
        address nftAddress,
        uint256 nftTokenID
    ) external {
        INFTOracle nftOracle = INFTOracle(addressesProvider.getNFTOracle());

        // Check if nft collection is supported
        require(
            nftOracle.isCollectionSupported(nftAddress),
            "NFT COllection is not supported"
        );

        // Check if borrow amount exceeds allowed amount
        require(
            amount <= nftOracle.getMaxCollateral(msg.sender, nftAddress),
            "Amount exceeds allowed by collateral"
        );

        // Check if the reserve has enough underlying to borrow
        require(
            amount <= IReserve(reserveAdress).getUnderlyingBalance(),
            "Amount exceeds reserve balance"
        );

        // Check if the borrower owns the asset
        require(
            IERC721Upgradeable(nftAddress).ownerOf(nftTokenID) == msg.sender,
            "Asset not owned by user"
        );
    }

    function validateRepay(
        IMarketAddressesProvider addressesProvider,
        uint256 loanId
    ) external view {
        ILoanCenter loanCenter = ILoanCenter(addressesProvider.getLoanCenter());
        //Require that loan exists
        DataTypes.LoanData memory loanData = loanCenter.getLoan(loanId);
        require(
            loanData.state != DataTypes.LoanState.None,
            "Loan does not exist"
        );

        // Check if caller trying to pay loan is borrower
        require(msg.sender == loanData.borrower, "Caller is not loan borrower");

        // Check the user has enough balance to repay
        uint256 balance = IERC20Upgradeable(
            IReserve(loanData.reserve).getAsset()
        ).balanceOf(msg.sender);
        require(
            balance >= loanCenter.getLoanDebt(loanId),
            "Balance is lower than loan debt"
        );
    }

    function validateLiquidation(
        IMarketAddressesProvider addressesProvider,
        uint256 loanId
    ) external {
        //Require that loan exists
        DataTypes.LoanData memory loanData = ILoanCenter(
            addressesProvider.getLoanCenter()
        ).getLoan(loanId);
        require(
            loanData.state != DataTypes.LoanState.None,
            "Loan does not exist"
        );

        // Check if collateral / debt relation allows for liquidation
        require(
            INFTOracle(addressesProvider.getNFTOracle()).getMaxCollateral(
                msg.sender,
                loanData.nftAsset
            ) <
                ILoanCenter(addressesProvider.getLoanCenter()).getLoanDebt(
                    loanId
                ),
            "Collateral / Debt loan relation does not allow for liquidation."
        );

        // Check if caller has enough balance
        uint256 balance = IERC20Upgradeable(
            IReserve(loanData.reserve).getAsset()
        ).balanceOf(msg.sender);
        uint256 liquidationPrice = PercentageMath.percentMul(
            INFTOracle(addressesProvider.getNFTOracle())
                .getCollectionFloorPrice(loanData.nftAsset),
            PercentageMath.PERCENTAGE_FACTOR -
                IReserve(loanData.reserve).getLiquidationPenalty() +
                IReserve(loanData.reserve).getProtocolLiquidationFee()
        );

        require(
            balance >= liquidationPrice,
            "Balance lower than liquidation price"
        );
    }

    function validateNativeTokenDeposit(address nativeAsset, uint256 amount)
        external
        view
    {
        // Get balance of the user trying the deposit
        uint256 balance = IERC20Upgradeable(nativeAsset).balanceOf(msg.sender);

        require(amount <= balance, "Balance is lower than deposited amount");
    }

    function validateNativeTokenWithdraw(
        IMarketAddressesProvider addressesProvider,
        uint256 amount
    ) external view {
        INativeTokenVault vault = INativeTokenVault(
            addressesProvider.getNativeTokenVault()
        );

        require(
            // Check if the user has enough reserve balance for withdrawal
            amount <= vault.getMaximumWithdrawalAmount(msg.sender),
            "Withdrawal amount higher than permitted."
        );
    }

    function validateVote(
        IMarketAddressesProvider addressesProvider,
        uint256 amount,
        address collection
    ) external {
        INFTOracle nftOracle = INFTOracle(addressesProvider.getNFTOracle());
        INativeTokenVault vault = INativeTokenVault(
            addressesProvider.getNativeTokenVault()
        );
        uint256 freeVotes = vault.getUserFreeVotes(msg.sender);

        //Check if the user ahs enough free votes
        require(
            freeVotes >= amount,
            "Not enough voting power for requested amount"
        );

        // Check if nft collection is supported
        require(
            nftOracle.isCollectionSupported(collection),
            "NFT COllection is not supported"
        );
    }

    function validateRemoveVote(
        IMarketAddressesProvider addressesProvider,
        uint256 amount,
        address collection
    ) external {
        INFTOracle nftOracle = INFTOracle(addressesProvider.getNFTOracle());
        INativeTokenVault vault = INativeTokenVault(
            addressesProvider.getNativeTokenVault()
        );
        uint256 collectionVotes = vault.getUserCollectionVotes(
            msg.sender,
            collection
        );
        DataTypes.RemoveVoteRequest memory removeVoteRequest = vault
            .getRemoveVoteRequest(msg.sender, collection);

        // Check if we are within the unlock request window and amount
        require(
            block.timestamp > removeVoteRequest.timestamp + ONE_WEEK &&
                block.timestamp <
                removeVoteRequest.timestamp + ONE_WEEK + UNVOTE_WINDOW,
            "RemoveVote Request is not within valid timeframe"
        );

        require(
            removeVoteRequest.amount > amount,
            "RemoveVote Request amount is smaller than requested amount"
        );

        // Check if nft collection is supported
        require(
            nftOracle.isCollectionSupported(collection),
            "NFT COllection is not supported"
        );

        //Check if the user ahs enough free votes
        require(
            collectionVotes >= amount,
            "Not enough votes in selected collection"
        );
    }
}
