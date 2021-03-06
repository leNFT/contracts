// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.8.15;

import {DataTypes} from "../types/DataTypes.sol";
import {PercentageMath} from "../math/PercentageMath.sol";
import {INFTOracle} from "../../interfaces/INFTOracle.sol";
import {ITokenOracle} from "../../interfaces/ITokenOracle.sol";
import {IInterestRate} from "../../interfaces/IInterestRate.sol";
import {IAddressesProvider} from "../../interfaces/IAddressesProvider.sol";
import {IMarket} from "../../interfaces/IMarket.sol";
import {ILoanCenter} from "../../interfaces/ILoanCenter.sol";
import {IReserve} from "../../interfaces/IReserve.sol";
import {INativeTokenVault} from "../../interfaces/INativeTokenVault.sol";
import {LoanLogic} from "./LoanLogic.sol";
import {WithdrawRequestLogic} from "./WithdrawRequestLogic.sol";
import {IERC721Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC721/IERC721Upgradeable.sol";
import {IERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "hardhat/console.sol";

library ValidationLogic {
    uint256 internal constant ONE_DAY = 86400;
    uint256 internal constant ONE_WEEK = ONE_DAY * 7;
    uint256 internal constant UNVOTE_WINDOW = ONE_DAY * 2;
    using LoanLogic for DataTypes.LoanData;
    using WithdrawRequestLogic for DataTypes.WithdrawRequest;

    function validateDeposit(
        mapping(address => address) storage reserves,
        address asset,
        uint256 amount
    ) external view {
        // Check if the asset is supported
        require(reserves[asset] != address(0), "Asset not supported");

        // Get balance of the user trying the deposit
        uint256 balance = IERC20Upgradeable(asset).balanceOf(msg.sender);

        require(amount <= balance, "Balance is lower than deposited amount");

        // Check if deposit amount is bigger than 0
        require(amount > 0, "Deposit amount must be bigger than 0");
    }

    function validateWithdrawal(
        IAddressesProvider addressesProvider,
        mapping(address => address) storage reserves,
        address asset,
        uint256 amount
    ) external view {
        // Check if the asset is supported
        require(reserves[asset] != address(0), "Asset not supported");
        // Check if the utilization rate doesn't go above maximum

        uint256 maximumUtilizationRate = IReserve(reserves[asset])
            .getMaximumUtilizationRate();
        uint256 debt = IReserve(reserves[asset]).getDebt();
        uint256 underlyingBalance = IReserve(reserves[asset])
            .getUnderlyingBalance();
        uint256 updatedUtilizationRate = IInterestRate(
            addressesProvider.getInterestRate()
        ).calculateUtilizationRate(underlyingBalance - amount, debt);

        require(
            updatedUtilizationRate <= maximumUtilizationRate,
            "Reserve utilization rate too high"
        );

        // Check if the user has enough reserve balance for withdrawal
        require(
            amount <=
                IReserve(reserves[asset]).getMaximumWithdrawalAmount(
                    msg.sender
                ),
            "Amount too high"
        );

        // Check if withdrawal amount is bigger than 0
        require(amount > 0, "Withdrawal amount must be bigger than 0");
    }

    // Check if borrowing conditions are valid
    function validateBorrow(
        IAddressesProvider addressesProvider,
        mapping(address => address) storage reserves,
        address asset,
        uint256 amount,
        address nftAddress,
        uint256 nftTokenID
    ) external view {
        // Check if the asset is supported
        require(reserves[asset] != address(0), "Asset not supported");

        INFTOracle nftOracle = INFTOracle(addressesProvider.getNFTOracle());
        ITokenOracle tokenOracle = ITokenOracle(
            addressesProvider.getTokenOracle()
        );
        uint256 tokenETHPrice = tokenOracle.getTokenETHPrice(asset);
        uint256 pricePrecision = tokenOracle.getPricePrecision();

        // Check if nft collection is supported
        require(
            nftOracle.isCollectionSupported(nftAddress),
            "NFT COllection is not supported"
        );

        // Check if borrow amount exceeds allowed amount
        require(
            amount <=
                (nftOracle.getMaxETHCollateral(msg.sender, nftAddress) *
                    tokenETHPrice) /
                    pricePrecision,
            "Amount exceeds allowed by collateral"
        );

        // Check if the reserve has enough underlying to borrow
        require(
            amount <= IReserve(reserves[asset]).getUnderlyingBalance(),
            "Amount exceeds reserve balance"
        );

        // Check if borrow amount is bigger than 0
        require(amount > 0, "Borrow amount must be bigger than 0");

        // Check if the borrower owns the asset
        require(
            IERC721Upgradeable(nftAddress).ownerOf(nftTokenID) == msg.sender,
            "Asset not owned by user"
        );
    }

    function validateRepay(IAddressesProvider addressesProvider, uint256 loanId)
        external
        view
    {
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
        IAddressesProvider addressesProvider,
        uint256 loanId
    ) external view {
        //Require that loan exists
        DataTypes.LoanData memory loanData = ILoanCenter(
            addressesProvider.getLoanCenter()
        ).getLoan(loanId);
        require(
            loanData.state != DataTypes.LoanState.None,
            "Loan does not exist"
        );

        // Check if collateral / debt relation allows for liquidation
        address reserveAsset = IReserve(loanData.reserve).getAsset();
        ITokenOracle tokenOracle = ITokenOracle(
            addressesProvider.getTokenOracle()
        );
        uint256 tokenETHPrice = tokenOracle.getTokenETHPrice(reserveAsset);
        uint256 pricePrecision = tokenOracle.getPricePrecision();

        require(
            (INFTOracle(addressesProvider.getNFTOracle()).getMaxETHCollateral(
                msg.sender,
                loanData.nftAsset
            ) * tokenETHPrice) /
                pricePrecision <
                ILoanCenter(addressesProvider.getLoanCenter()).getLoanDebt(
                    loanId
                ),
            "Collateral / Debt loan relation does not allow for liquidation."
        );

        // Check if caller has enough balance
        uint256 balance = IERC20Upgradeable(reserveAsset).balanceOf(msg.sender);
        uint256 floorPrice = (INFTOracle(addressesProvider.getNFTOracle())
            .getCollectionETHFloorPrice(loanData.nftAsset) * tokenETHPrice) /
            pricePrecision;

        uint256 liquidationPrice = PercentageMath.percentMul(
            floorPrice,
            PercentageMath.PERCENTAGE_FACTOR -
                IReserve(loanData.reserve).getLiquidationPenalty() +
                IReserve(loanData.reserve).getLiquidationFee()
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

        require(amount > 0, "Deposit amount must be bigger than 0");
    }

    function validateNativeTokenWithdraw(
        IAddressesProvider addressesProvider,
        uint256 amount
    ) external view {
        INativeTokenVault vault = INativeTokenVault(
            addressesProvider.getNativeTokenVault()
        );

        DataTypes.WithdrawRequest memory withdrawRequest = vault
            .getWithdrawRequest(msg.sender);

        // Check if we are within the unlock request window and amount
        require(
            block.timestamp > withdrawRequest.timestamp + ONE_WEEK &&
                block.timestamp <
                withdrawRequest.timestamp + ONE_WEEK + UNVOTE_WINDOW,
            "Withdraw Request is not within valid timeframe"
        );

        require(
            withdrawRequest.amount >= amount,
            "Withdraw Request amount is smaller than requested amount"
        );

        require(
            // Check if the user has enough reserve balance for withdrawal
            amount <= vault.getMaximumWithdrawalAmount(msg.sender),
            "Withdrawal amount higher than permitted."
        );

        require(amount > 0, "Withdrawal amount must be bigger than 0");
    }

    function validateVote(
        IAddressesProvider addressesProvider,
        uint256 amount,
        address collection
    ) external view {
        INFTOracle nftOracle = INFTOracle(addressesProvider.getNFTOracle());
        INativeTokenVault vault = INativeTokenVault(
            addressesProvider.getNativeTokenVault()
        );
        uint256 freeVotes = vault.getUserFreeVotes(msg.sender);

        //Check if the user has enough free votes
        require(
            freeVotes >= amount,
            "Not enough voting power for requested amount"
        );

        // Check if the input amount is bigger than 0
        require(amount > 0, "Vote amount must be bigger than 0");

        // Check if nft collection is supported
        require(
            nftOracle.isCollectionSupported(collection),
            "NFT COllection is not supported"
        );
    }

    function validateRemoveVote(
        IAddressesProvider addressesProvider,
        uint256 amount,
        address collection
    ) external view {
        INFTOracle nftOracle = INFTOracle(addressesProvider.getNFTOracle());
        INativeTokenVault vault = INativeTokenVault(
            addressesProvider.getNativeTokenVault()
        );
        uint256 collectionVotes = vault.getUserCollectionVotes(
            msg.sender,
            collection
        );

        // Check if nft collection is supported
        require(
            nftOracle.isCollectionSupported(collection),
            "NFT COllection is not supported"
        );

        // Check if the input amount is bigger than 0
        require(amount > 0, "Remove vote amount must be bigger than 0");

        //Check if the user has enough free votes
        require(
            collectionVotes >= amount,
            "Not enough votes in selected collection"
        );
    }

    function validateCreateWithdrawRequest(
        IAddressesProvider addressesProvider,
        uint256 amount
    ) external view {
        INativeTokenVault vault = INativeTokenVault(
            addressesProvider.getNativeTokenVault()
        );

        // Check if the input amount is bigger than 0
        require(amount > 0, "Withdraw request amount must be bigger than 0");

        uint256 maximumWithdrawalAmount = vault.getMaximumWithdrawalAmount(
            msg.sender
        );
        // User needs to have less than or equal balance in the vault to withdraw
        require(
            amount <= maximumWithdrawalAmount,
            "Requested amount is higher than vault balance"
        );
    }
}
