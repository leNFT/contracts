// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.8.17;

import {DataTypes} from "../types/DataTypes.sol";
import {PercentageMath} from "../math/PercentageMath.sol";
import {ValidationLogic} from "./ValidationLogic.sol";
import {IAddressesProvider} from "../../interfaces/IAddressesProvider.sol";
import {INFTOracle} from "../../interfaces/INFTOracle.sol";
import {INFTOracle} from "../../interfaces/INFTOracle.sol";
import {ILoanCenter} from "../../interfaces/ILoanCenter.sol";
import {ILendingPool} from "../../interfaces/ILendingPool.sol";
import {IDebtToken} from "../../interfaces/IDebtToken.sol";
import {IGenesisNFT} from "../../interfaces/IGenesisNFT.sol";
import {IERC721Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC721/IERC721Upgradeable.sol";
import {IERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import {Trustus} from "../../protocol/Trustus/Trustus.sol";

library BorrowLogic {
    function borrow(
        IAddressesProvider addressesProvider,
        mapping(address => mapping(address => address)) storage pools,
        DataTypes.BorrowParams memory params
    ) external returns (uint256) {
        // Validate the movement
        ValidationLogic.validateBorrow(addressesProvider, pools, params);

        // Transfer the collateral to the loan center
        IERC721Upgradeable(params.nftAddress).safeTransferFrom(
            params.caller,
            addressesProvider.getLoanCenter(),
            params.nftTokenID
        );

        // Get the borrow rate index
        uint256 borrowRate = ILendingPool(
            pools[params.nftAddress][params.asset]
        ).getBorrowRate();

        // Get max LTV for this collection
        ILoanCenter loanCenter = ILoanCenter(addressesProvider.getLoanCenter());
        uint256 maxLTV = loanCenter.getCollectionMaxCollaterization(
            params.nftAddress
        );

        // Get boost for this user and collection
        uint256 boost = 0;

        // If a genesis NFT was used with this loan
        if (params.genesisNFTId != 0) {
            boost = IGenesisNFT(addressesProvider.getGenesisNFT()).getLTVBoost();

            // Lock genesis NFT to this loan
            IGenesisNFT(addressesProvider.getGenesisNFT()).setActiveState(
                params.genesisNFTId,
                true
            );
        }

        // Create the loan
        uint256 loanId = loanCenter.createLoan(
            params.onBehalfOf,
            pools[params.nftAddress][params.asset],
            params.amount,
            maxLTV,
            boost,
            params.genesisNFTId,
            params.nftAddress,
            params.nftTokenID,
            borrowRate
        );

        // Mint the token representing the debt
        IDebtToken(addressesProvider.getDebtToken()).mint(
            params.onBehalfOf,
            loanId
        );

        //Activate Loan
        loanCenter.activateLoan(loanId);

        // Send the principal to the borrower
        ILendingPool(pools[params.nftAddress][params.asset]).transferUnderlying(
                params.caller,
                params.amount,
                borrowRate
            );

        return loanId;
    }

    function repay(
        IAddressesProvider addressesProvider,
        DataTypes.RepayParams memory params
    ) external {
        // Validate the movement
        ValidationLogic.validateRepay(addressesProvider, params);

        // Get the loan
        ILoanCenter loanCenter = ILoanCenter(addressesProvider.getLoanCenter());
        DataTypes.LoanData memory loanData = loanCenter.getLoan(params.loanId);
        uint256 interest = loanCenter.getLoanInterest(params.loanId);

        // If we are paying the entire loan debt
        if (params.amount == loanCenter.getLoanDebt(params.loanId)) {
            // Return the principal + interest
            ILendingPool(loanData.pool).receiveUnderlying(
                params.caller,
                loanData.amount,
                loanData.borrowRate,
                interest
            );

            loanCenter.repayLoan(params.loanId);

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
            IDebtToken(addressesProvider.getDebtToken()).burn(params.loanId);
        }
        // User is sending less than the total debt
        else {
            // User is sending less than the interest
            if (params.amount <= interest) {
                ILendingPool(loanData.pool).receiveUnderlying(
                    params.caller,
                    0,
                    loanData.borrowRate,
                    params.amount
                );

                // Calculate how much time the user has paid off with sent amount
                loanCenter.updateLoanDebtTimestamp(
                    params.loanId,
                    loanData.debtTimestamp +
                        ((365 days *
                            params.amount *
                            PercentageMath.PERCENTAGE_FACTOR) /
                            (loanData.amount * loanData.borrowRate))
                );
            }
            // User is sending the full interest and closing part of the loan
            else {
                ILendingPool(loanData.pool).receiveUnderlying(
                    params.caller,
                    params.amount - interest,
                    loanData.borrowRate,
                    interest
                );
                loanCenter.updateLoanDebtTimestamp(
                    params.loanId,
                    block.timestamp
                );
                loanCenter.updateLoanAmount(
                    params.loanId,
                    loanData.amount - (params.amount - interest)
                );
            }
        }
    }
}
