// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.8.17;

import {DataTypes} from "../types/DataTypes.sol";
import {PercentageMath} from "../math/PercentageMath.sol";
import {ValidationLogic} from "./ValidationLogic.sol";
import {IAddressesProvider} from "../../interfaces/IAddressesProvider.sol";
import {INFTOracle} from "../../interfaces/INFTOracle.sol";
import {INFTOracle} from "../../interfaces/INFTOracle.sol";
import {ILoanCenter} from "../../interfaces/ILoanCenter.sol";
import {IReserve} from "../../interfaces/IReserve.sol";
import {IDebtToken} from "../../interfaces/IDebtToken.sol";
import {IGenesisNFT} from "../../interfaces/IGenesisNFT.sol";
import {INativeTokenVault} from "../../interfaces/INativeTokenVault.sol";
import {IERC721Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC721/IERC721Upgradeable.sol";
import {IERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import {Trustus} from "../../protocol/Trustus.sol";

library BorrowLogic {
    function borrow(
        IAddressesProvider addressesProvider,
        mapping(address => mapping(address => address)) storage reserves,
        address depositor,
        address asset,
        uint256 amount,
        address nftAddress,
        uint256 nftTokenID,
        uint256 genesisNFTId,
        bytes32 request,
        Trustus.TrustusPacket calldata packet
    ) external returns (uint256) {
        // Validate the movement
        ValidationLogic.validateBorrow(
            addressesProvider,
            reserves,
            asset,
            amount,
            nftAddress,
            nftTokenID,
            genesisNFTId,
            request,
            packet
        );

        // Transfer the collateral
        IERC721Upgradeable(nftAddress).safeTransferFrom(
            msg.sender,
            addressesProvider.getLoanCenter(),
            nftTokenID
        );

        // Get the borrow rate index
        uint256 borrowRate = IReserve(reserves[nftAddress][asset])
            .getBorrowRate();

        // Get max LTV for this collection
        ILoanCenter loanCenter = ILoanCenter(addressesProvider.getLoanCenter());
        uint256 maxLTV = loanCenter.getCollectionMaxCollaterization(nftAddress);

        // Get boost for this user and collection
        uint256 boost = INativeTokenVault(
            addressesProvider.getNativeTokenVault()
        ).getVoteCollateralizationBoost(msg.sender, nftAddress);

        // If a genesis NFT was used with this loan
        if (genesisNFTId != 0) {
            boost += IGenesisNFT(addressesProvider.getGenesisNFT())
                .getLTVBoost();

            // Lock genesis NFT to this loan
            IGenesisNFT(addressesProvider.getGenesisNFT()).setActiveState(
                genesisNFTId,
                true
            );
        }

        // Create the loan
        uint256 loanId = loanCenter.createLoan(
            msg.sender,
            reserves[nftAddress][asset],
            amount,
            maxLTV,
            boost,
            genesisNFTId,
            nftAddress,
            nftTokenID,
            borrowRate
        );

        // Mint the token representing the debt
        IDebtToken(addressesProvider.getDebtToken()).mint(msg.sender, loanId);

        //Activate Loan after the principal has been sent
        loanCenter.activateLoan(loanId);

        // Send the principal to the borrower
        IReserve(reserves[nftAddress][asset]).transferUnderlying(
            depositor,
            amount,
            borrowRate
        );

        return loanId;
    }

    function repay(
        IAddressesProvider addressesProvider,
        uint256 loanId,
        uint256 amount
    ) external {
        // Validate the movement
        ValidationLogic.validateRepay(addressesProvider, loanId, amount);

        // Get the loan
        ILoanCenter loanCenter = ILoanCenter(addressesProvider.getLoanCenter());
        DataTypes.LoanData memory loanData = loanCenter.getLoan(loanId);
        uint256 interest = loanCenter.getLoanInterest(loanId);

        // If we are paying the entire loan debt
        if (amount == loanCenter.getLoanDebt(loanId)) {
            // Return the principal + interest
            IReserve(loanData.reserve).receiveUnderlying(
                loanData.borrower,
                loanData.amount,
                loanData.borrowRate,
                interest
            );

            loanCenter.repayLoan(loanId);

            // Unlock Genesis NFT
            if (loanData.genesisNFTId != 0) {
                // Lock genesis NFT to this loan
                IGenesisNFT(addressesProvider.getGenesisNFT()).setActiveState(
                    loanData.genesisNFTId,
                    false
                );
            }

            // Transfer the collateral back to the owner
            IERC721Upgradeable(loanData.nftAsset).safeTransferFrom(
                addressesProvider.getLoanCenter(),
                loanData.borrower,
                loanData.nftTokenId
            );

            // Burn the token representing the debt
            IDebtToken(addressesProvider.getDebtToken()).burn(loanId);
        }
        // User is sending less than the total debt
        else {
            // User is sending less than the interest
            if (amount <= interest) {
                IReserve(loanData.reserve).receiveUnderlying(
                    loanData.borrower,
                    0,
                    loanData.borrowRate,
                    amount
                );

                // Calculate how much time the user has paid off with sent amount
                loanCenter.updateLoanDebtTimestamp(
                    loanId,
                    loanData.debtTimestamp +
                        ((365 days *
                            amount *
                            PercentageMath.PERCENTAGE_FACTOR) /
                            (loanData.amount * loanData.borrowRate))
                );
            }
            // User is sending the full interest and closing part of the loan
            else {
                IReserve(loanData.reserve).receiveUnderlying(
                    loanData.borrower,
                    amount - interest,
                    loanData.borrowRate,
                    interest
                );
                loanCenter.updateLoanDebtTimestamp(loanId, block.timestamp);
                loanCenter.updateLoanAmount(
                    loanId,
                    loanData.amount - (amount - interest)
                );
            }
        }
    }
}
