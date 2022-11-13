// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.8.17;

import {DataTypes} from "../types/DataTypes.sol";
import {PercentageMath} from "../math/PercentageMath.sol";
import {INFTOracle} from "../../interfaces/INFTOracle.sol";
import {ITokenOracle} from "../../interfaces/ITokenOracle.sol";
import {IInterestRate} from "../../interfaces/IInterestRate.sol";
import {IAddressesProvider} from "../../interfaces/IAddressesProvider.sol";
import {IMarket} from "../../interfaces/IMarket.sol";
import {ILoanCenter} from "../../interfaces/ILoanCenter.sol";
import {IGenesisNFT} from "../../interfaces/IGenesisNFT.sol";
import {IReserve} from "../../interfaces/IReserve.sol";
import {INativeTokenVault} from "../../interfaces/INativeTokenVault.sol";
import {WithdrawalRequestLogic} from "./WithdrawalRequestLogic.sol";
import {IERC4626Upgradeable} from "@openzeppelin/contracts-upgradeable/interfaces/IERC4626Upgradeable.sol";
import {IERC721Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC721/IERC721Upgradeable.sol";
import {IERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import {Trustus} from "../../protocol/Trustus/Trustus.sol";
import "hardhat/console.sol";

library ValidationLogic {
    uint256 internal constant ONE_DAY = 86400;
    uint256 internal constant ONE_WEEK = ONE_DAY * 7;
    uint256 internal constant UNVOTE_WINDOW = ONE_DAY * 2;
    using WithdrawalRequestLogic for DataTypes.WithdrawalRequest;

    function validateDeposit(DataTypes.DepositParams memory params)
        external
        view
    {
        // Get balance of the user trying the deposit
        require(
            params.amount <=
                IERC20Upgradeable(IReserve(params.reserve).getAsset())
                    .balanceOf(params.initiator),
            "Balance is lower than deposited amount"
        );

        // Check if deposit amount is bigger than 0
        require(params.amount > 0, "Deposit amount must be bigger than 0");

        // Check if reserve will exceed maximum permitted amount
        require(
            params.amount + IReserve(params.reserve).getTVL() <
                IReserve(params.reserve).getTVLSafeguard(),
            "Reserve exceeds safeguarded limit"
        );
    }

    function validateWithdrawal(
        IAddressesProvider addressesProvider,
        DataTypes.WithdrawalParams memory params
    ) external view {
        // Check if the utilization rate doesn't go above maximum
        uint256 maximumUtilizationRate = IReserve(params.reserve)
            .getMaximumUtilizationRate();
        uint256 debt = IReserve(params.reserve).getDebt();
        uint256 underlyingBalance = IReserve(params.reserve)
            .getUnderlyingBalance();
        uint256 updatedUtilizationRate = IInterestRate(
            addressesProvider.getInterestRate()
        ).calculateUtilizationRate(underlyingBalance - params.amount, debt);

        require(
            updatedUtilizationRate <= maximumUtilizationRate,
            "Reserve utilization rate too high"
        );

        // Check if the user has enough reserve balance for withdrawal
        require(
            params.amount <=
                IReserve(params.reserve).getMaximumWithdrawalAmount(
                    params.initiator
                ),
            "Amount too high"
        );

        // Check if withdrawal amount is bigger than 0
        require(params.amount > 0, "Withdrawal amount must be bigger than 0");
    }

    // Check if borrowing conditions are valid
    function validateBorrow(
        IAddressesProvider addressesProvider,
        mapping(address => mapping(address => address)) storage reserves,
        DataTypes.BorrowParams memory params
    ) external view {
        // Check if the asset is supported
        require(
            reserves[params.nftAddress][params.asset] != address(0),
            "No reserve for asset and collection"
        );

        ITokenOracle tokenOracle = ITokenOracle(
            addressesProvider.getTokenOracle()
        );
        uint256 assetETHPrice = tokenOracle.getTokenETHPrice(params.asset);
        uint256 pricePrecision = tokenOracle.getPricePrecision();

        // Get boost for this user and collection
        uint256 boost = INativeTokenVault(
            addressesProvider.getNativeTokenVault()
        ).getLTVBoost(params.initiator, params.nftAddress);

        // Get boost from genesis NFTs
        IGenesisNFT genesisNFT = IGenesisNFT(addressesProvider.getGenesisNFT());
        if (params.genesisNFTId != 0) {
            // Require owner is the borrower
            require(
                genesisNFT.ownerOf(params.genesisNFTId) == params.initiator,
                "Caller is not owner of Genesis NFT"
            );
            //Require that the NFT is not being used
            require(
                genesisNFT.getActiveState(params.genesisNFTId) == false,
                "Genesis NFT currently being used by another loan"
            );

            boost += genesisNFT.getLTVBoost();
        }

        // Get asset ETH price
        uint256 collateralETHPrice = INFTOracle(
            addressesProvider.getNFTOracle()
        ).getTokenETHPrice(
                params.nftAddress,
                params.nftTokenID,
                params.request,
                params.packet
            );

        // Check if borrow amount exceeds allowed amount
        require(
            params.amount <=
                (PercentageMath.percentMul(
                    collateralETHPrice,
                    ILoanCenter(addressesProvider.getLoanCenter())
                        .getCollectionMaxCollaterization(params.nftAddress) +
                        boost
                ) * pricePrecision) /
                    assetETHPrice,
            "Amount exceeds allowed by collateral"
        );

        // Check if the reserve has enough underlying to borrow
        require(
            params.amount <=
                IReserve(reserves[params.nftAddress][params.asset])
                    .getUnderlyingBalance(),
            "Amount exceeds reserve balance"
        );

        // Check if borrow amount is bigger than 0
        require(params.amount > 0, "Borrow amount must be bigger than 0");

        // Check if the borrower owns the asset
        require(
            IERC721Upgradeable(params.nftAddress).ownerOf(params.nftTokenID) ==
                params.initiator,
            "Asset not owned by user"
        );
    }

    function validateRepay(
        IAddressesProvider addressesProvider,
        DataTypes.RepayParams memory params
    ) external view {
        ILoanCenter loanCenter = ILoanCenter(addressesProvider.getLoanCenter());
        //Require that loan exists
        DataTypes.LoanData memory loanData = loanCenter.getLoan(params.loanId);
        require(
            loanData.state != DataTypes.LoanState.None,
            "Loan does not exist"
        );

        // Check if caller trying to pay loan is borrower
        require(
            params.initiator == loanData.borrower,
            "Caller is not loan borrower"
        );

        // Check the user has enough balance to repay
        require(
            IERC20Upgradeable(IReserve(loanData.reserve).getAsset()).balanceOf(
                params.initiator
            ) >= params.amount,
            "Balance is lower than repay amount"
        );

        // Check if user is over paying
        require(params.amount <= loanCenter.getLoanDebt(params.loanId));
    }

    function validateLiquidation(
        IAddressesProvider addressesProvider,
        DataTypes.LiquidationParams memory params
    ) external view {
        //Require the loan exists
        ILoanCenter loanCenter = ILoanCenter(addressesProvider.getLoanCenter());
        DataTypes.LoanData memory loanData = loanCenter.getLoan(params.loanId);
        require(
            loanData.state != DataTypes.LoanState.None,
            "Loan does not exist"
        );

        // Check if collateral / debt relation allows for liquidation
        address reserveAsset = IReserve(loanData.reserve).getAsset();
        ITokenOracle tokenOracle = ITokenOracle(
            addressesProvider.getTokenOracle()
        );
        uint256 baseTokenETHPrice = tokenOracle.getTokenETHPrice(reserveAsset);
        uint256 pricePrecision = tokenOracle.getPricePrecision();

        require(
            (loanCenter.getLoanMaxETHCollateral(
                params.loanId,
                params.request,
                params.packet
            ) * pricePrecision) /
                baseTokenETHPrice <
                loanCenter.getLoanDebt(params.loanId),
            "Collateral / Debt loan relation does not allow for liquidation."
        );

        (uint256 liquidationPrice, ) = loanCenter.getLoanLiquidationPrice(
            params.loanId,
            params.request,
            params.packet
        );

        // Check if caller has enough balance
        uint256 balance = IERC20Upgradeable(reserveAsset).balanceOf(msg.sender);
        require(
            balance >= liquidationPrice,
            "Balance lower than liquidation price"
        );
    }

    function validateCreateWithdrawalRequest(
        IAddressesProvider addressesProvider
    ) external view {
        DataTypes.WithdrawalRequest
            memory withdrawalRequest = INativeTokenVault(
                addressesProvider.getNativeTokenVault()
            ).getWithdrawalRequest(msg.sender);

        // Check if we are creating outside the request window
        if (withdrawalRequest.created == true) {
            require(
                block.timestamp > withdrawalRequest.timestamp + ONE_WEEK,
                "Withdraw request already created"
            );
        }
    }

    function validateNativeTokenWithdraw(
        IAddressesProvider addressesProvider,
        uint256 shares
    ) external view {
        DataTypes.WithdrawalRequest
            memory withdrawalRequest = INativeTokenVault(
                addressesProvider.getNativeTokenVault()
            ).getWithdrawalRequest(msg.sender);

        // Check if the request was created
        require(
            withdrawalRequest.created == true,
            "No withdraw request created"
        );

        // Check if we are within the unlock request window and amount
        require(
            block.timestamp > withdrawalRequest.timestamp + ONE_WEEK &&
                block.timestamp <
                withdrawalRequest.timestamp + ONE_WEEK + UNVOTE_WINDOW,
            "Withdraw Request is not within valid timeframe"
        );

        require(
            withdrawalRequest.amount >= shares,
            "Withdraw Request amount is smaller than requested amount"
        );

        require(
            INativeTokenVault(addressesProvider.getNativeTokenVault())
                .getUserFreeVotes(msg.sender) >= shares,
            "Not enough free votes"
        );
    }

    function validateVote(IAddressesProvider addressesProvider, uint256 shares)
        external
        view
    {
        //Check if the user has enough free votes
        require(
            INativeTokenVault(addressesProvider.getNativeTokenVault())
                .getUserFreeVotes(msg.sender) >= shares,
            "Not enough voting power for requested amount"
        );

        // Check if the input amount is bigger than 0
        require(shares > 0, "Vote amount must be bigger than 0");
    }

    function validateRemoveVote(
        IAddressesProvider addressesProvider,
        uint256 shares,
        address collection
    ) external view {
        // Check if user has no active loans in voted collection
        require(
            ILoanCenter(addressesProvider.getLoanCenter()).getActiveLoansCount(
                msg.sender,
                collection
            ) == 0,
            "User has active loans in collection"
        );

        // Check if the input amount is bigger than 0
        require(shares > 0, "Remove vote amount must be bigger than 0");

        //Check if the user has enough free votes
        require(
            INativeTokenVault(addressesProvider.getNativeTokenVault())
                .getUserCollectionVotes(msg.sender, collection) >= shares,
            "Not enough votes in selected collection"
        );
    }
}
