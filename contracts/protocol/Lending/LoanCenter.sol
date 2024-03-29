// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.8.19;

import {ILoanCenter} from "../../interfaces/ILoanCenter.sol";
import {PercentageMath} from "../../libraries/utils/PercentageMath.sol";
import {DataTypes} from "../../libraries/types/DataTypes.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {IAddressProvider} from "../../interfaces/IAddressProvider.sol";
import {SafeCast} from "../../libraries/utils/SafeCast.sol";
import {ILendingPool} from "../../interfaces/ILendingPool.sol";

/// @title LoanCenter contract
/// @author leNFT
/// @notice Manages loans
/// @dev Keeps the list of loans, their states and their liquidation data
contract LoanCenter is ILoanCenter, OwnableUpgradeable {
    // NFT address + NFT ID to loan ID mapping
    mapping(address => mapping(uint256 => uint256)) private _nftToLoanId;

    // Loan ID to loan info mapping
    mapping(uint256 => DataTypes.LoanData) private _loans;

    // Loan id to liquidation data
    mapping(uint256 => DataTypes.LoanLiquidationData)
        private _loansLiquidationData;

    uint256 private _loansCount;
    IAddressProvider private immutable _addressProvider;

    // Collection to CollectionRiskParameters (max LTV and liquidation threshold)
    mapping(address => DataTypes.CollectionRiskParameters)
        private _collectionsRiskParameters;

    // Default values for Collection Risk Parameters
    uint256 private _defaultLiquidationThreshold;
    uint256 private _defaultMaxLTV;

    // Mapping from address to active loans
    mapping(address => uint256[]) private _activeLoans;

    modifier onlyMarket() {
        _requireOnlyMarket();
        _;
    }

    modifier loanExists(uint256 loanId) {
        _requireLoanExists(loanId);
        _;
    }

    modifier loanAuctioned(uint256 loanId) {
        _requireLoanAuctioned(loanId);
        _;
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor(IAddressProvider addressProvider) {
        _addressProvider = addressProvider;
        _disableInitializers();
    }

    /// @notice Initializes the contract
    /// @param defaultLiquidationThreshold The default liquidation threshold
    /// @param defaultMaxLTV The default max LTV
    function initialize(
        uint256 defaultLiquidationThreshold,
        uint256 defaultMaxLTV
    ) external initializer {
        __Ownable_init();
        _defaultLiquidationThreshold = defaultLiquidationThreshold;
        _defaultMaxLTV = defaultMaxLTV;
    }

    /// @notice Create a new loan with the specified parameters and add it to the loans list
    /// @dev Only the market contract can call this function
    /// @param borrower The address of the borrower
    /// @param pool The address of the lending pool
    /// @param amount The amount of the lending pool token to be borrowed
    /// @param genesisNFTId The ID of the genesis NFT
    /// @param nftAddress The address of the NFT contract
    /// @param nftTokenIds An array of NFT token IDs that will be used as collateral
    /// @param borrowRate The interest rate for the loan
    /// @return The ID of the newly created loan
    function createLoan(
        address borrower,
        address pool,
        uint256 amount,
        uint256 genesisNFTId,
        address nftAddress,
        uint256[] calldata nftTokenIds,
        uint256 borrowRate
    ) external override onlyMarket returns (uint256) {
        _loans[_loansCount] = DataTypes.LoanData({
            owner: borrower,
            amount: amount,
            nftTokenIds: nftTokenIds,
            nftAsset: nftAddress,
            borrowRate: SafeCast.toUint16(borrowRate),
            initTimestamp: SafeCast.toUint40(block.timestamp),
            debtTimestamp: SafeCast.toUint40(block.timestamp),
            pool: pool,
            genesisNFTId: SafeCast.toUint16(genesisNFTId),
            state: DataTypes.LoanState.Active
        });

        // Add NFT to loanId mapping
        for (uint256 i = 0; i < nftTokenIds.length; i++) {
            _nftToLoanId[nftAddress][nftTokenIds[i]] = _loansCount;
        }

        // Add loan to active loans
        _activeLoans[borrower].push(_loansCount);

        // Increment the loans count and then return it
        return _loansCount++;
    }

    /// @notice Repay a loan by setting its state to Repaid
    /// @dev Only the market contract can call this function
    /// @param loanId The ID of the loan to be repaid
    function repayLoan(uint256 loanId) external override onlyMarket {
        // Update loan state
        _loans[loanId].state = DataTypes.LoanState.Repaid;

        // Close the loan
        _closeLoan(loanId);
    }

    /// @notice Liquidate a loan by setting its state to Liquidated and freeing up the NFT collateral pointers
    /// @dev Only the market contract can call this function
    /// @param loanId The ID of the loan to be liquidated
    function liquidateLoan(uint256 loanId) external override onlyMarket {
        // Update loan state
        _loans[loanId].state = DataTypes.LoanState.Liquidated;

        // Close the loan
        _closeLoan(loanId);
    }

    /// @notice Start an auction for a loan
    /// @dev Sets its state to Auctioned and creates the liquidation data
    /// @dev Only the market contract can call this function
    /// @param loanId The ID of the loan to be auctioned
    /// @param user The address of the user who started the auction
    /// @param bid The initial bid for the auction
    function auctionLoan(
        uint256 loanId,
        address user,
        uint256 bid
    ) external override onlyMarket {
        // Update state
        _loans[loanId].state = DataTypes.LoanState.Auctioned;

        // Create the liquidation data
        _loansLiquidationData[loanId] = DataTypes.LoanLiquidationData({
            auctioneer: user,
            liquidator: user,
            auctionStartTimestamp: SafeCast.toUint40(block.timestamp),
            auctionMaxBid: bid
        });
    }

    /// @notice Update the auction data for a loan
    /// @dev Only the market contract can call this function
    /// @param loanId The ID of the loan to be updated
    /// @param user The address of the user who updated the auction
    /// @param bid The new bid for the auction
    function updateLoanAuctionBid(
        uint256 loanId,
        address user,
        uint256 bid
    ) external override onlyMarket {
        // Update the liquidation data
        _loansLiquidationData[loanId].liquidator = user;
        _loansLiquidationData[loanId].auctionMaxBid = bid;
    }

    /// @notice Changes the Risk Parameters for a collection.
    /// @param collection The address of the collection to change the max collaterization price for.
    /// @param maxLTV The new max LTV to set (10000 = 100%).
    /// @param liquidationThreshold The new liquidation Threshold to set (10000 = 100%).
    function setCollectionRiskParameters(
        address collection,
        uint256 maxLTV,
        uint256 liquidationThreshold
    ) external onlyOwner {
        //Set the max collaterization
        _collectionsRiskParameters[collection] = DataTypes
            .CollectionRiskParameters({
                maxLTV: SafeCast.toUint16(maxLTV),
                liquidationThreshold: SafeCast.toUint16(liquidationThreshold)
            });
    }

    /// @notice Updates the debt timestamp of a loan.
    /// @param loanId The ID of the loan to update.
    /// @param newDebtTimestamp The new debt timestamp to set.
    function updateLoanDebtTimestamp(
        uint256 loanId,
        uint256 newDebtTimestamp
    ) external override onlyMarket {
        _loans[loanId].debtTimestamp = uint40(newDebtTimestamp);
    }

    /// @notice Updates the amount of a loan.
    /// @param loanId The ID of the loan to update.
    /// @param newAmount The new amount to set.
    function updateLoanAmount(
        uint256 loanId,
        uint256 newAmount
    ) external override onlyMarket {
        _loans[loanId].amount = newAmount;
    }

    /// @notice Get the number of loans in the loans list
    /// @return The number of loans
    function getLoansCount() external view override returns (uint256) {
        return _loansCount;
    }

    /// @notice Get the active loans for a user
    /// @param user The address of the user
    /// @return An array of loan IDs
    function getUserActiveLoans(
        address user
    ) external view returns (uint256[] memory) {
        return _activeLoans[user];
    }

    /// @notice Get a loan by its ID
    /// @param loanId The ID of the loan to be retrieved
    /// @return The loan data
    function getLoan(
        uint256 loanId
    )
        external
        view
        override
        loanExists(loanId)
        returns (DataTypes.LoanData memory)
    {
        return _loans[loanId];
    }

    /// @notice Get the liquidation data for a loan
    /// @param loanId The loan ID associated with the liquidation data to be retrieved
    function getLoanLiquidationData(
        uint256 loanId
    )
        external
        view
        override
        loanExists(loanId)
        loanAuctioned(loanId)
        returns (DataTypes.LoanLiquidationData memory)
    {
        return _loansLiquidationData[loanId];
    }

    /// @notice Get the maximum debt a loan can reach before entering the liquidation zone
    /// @param loanId The ID of the loan to be queried
    /// @param collateralPrice The price of the tokens collateralizing the loan
    /// @return The maximum debt quoted in the same asset as the price of the collateral tokens
    function getLoanMaxDebt(
        uint256 loanId,
        uint256 collateralPrice
    ) external view override loanExists(loanId) returns (uint256) {
        return
            PercentageMath.percentMul(
                collateralPrice,
                getCollectionLiquidationThreshold(_loans[loanId].nftAsset)
            );
    }

    /// @notice Get the loan ID associated with the specified NFT
    /// @param nftAddress The address of the NFT contract
    /// @param nftTokenId The ID of the NFT
    /// @return The ID of the loan associated with the NFT
    function getNFTLoanId(
        address nftAddress,
        uint256 nftTokenId
    ) external view override returns (uint256) {
        return _nftToLoanId[nftAddress][nftTokenId];
    }

    /// @notice Get the debt owed on a loan
    /// @param loanId The ID of the loan
    /// @return The total amount of debt owed on the loan quoted in the same asset of the loan's lending pool
    function getLoanDebt(
        uint256 loanId
    ) external view override loanExists(loanId) returns (uint256) {
        return _getLoanDebt(loanId);
    }

    /// @notice Get the interest owed on a loan
    /// @param loanId The ID of the loan
    /// @return The amount of interest owed on the loan
    function getLoanInterest(
        uint256 loanId
    ) external view override loanExists(loanId) returns (uint256) {
        return _getLoanInterest(loanId, block.timestamp);
    }

    /// @notice Get the NFT token IDs associated with a loan
    /// @param loanId The ID of the loan
    /// @return An array of the NFT token IDs associated with the loan
    function getLoanTokenIds(
        uint256 loanId
    ) external view override loanExists(loanId) returns (uint256[] memory) {
        return _loans[loanId].nftTokenIds;
    }

    /// @notice Get the NFT contract address associated with a loan
    /// @param loanId The ID of the loan
    /// @return The address of the NFT contract associated with the loan
    function getLoanCollectionAddress(
        uint256 loanId
    ) external view override loanExists(loanId) returns (address) {
        return _loans[loanId].nftAsset;
    }

    /// @notice Get the lending pool address associated with a loan
    /// @param loanId The ID of the loan
    /// @return The address of the lending pool associated with the loan
    function getLoanLendingPool(
        uint256 loanId
    ) external view override loanExists(loanId) returns (address) {
        return _loans[loanId].pool;
    }

    /// @notice Get the state of a loan
    /// @param loanId The ID of the loan
    /// @return The state of the loan
    function getLoanState(
        uint256 loanId
    ) external view override returns (DataTypes.LoanState) {
        return _loans[loanId].state;
    }

    /// @notice Get auctioner fee for a repayment of an auctioned loan
    /// @param loanId The ID of the loan
    /// @return The auctioner fee
    function getLoanAuctioneerFee(
        uint256 loanId
    ) external view loanExists(loanId) loanAuctioned(loanId) returns (uint256) {
        return
            PercentageMath.percentMul(
                _getLoanDebt(loanId),
                ILendingPool(_loans[loanId].pool)
                    .getPoolConfig()
                    .auctioneerFeeRate
            );
    }

    /// @notice Get the owner of a loan
    /// @param loanId The ID of the loan
    /// @return The address of the owner of the loan
    function getLoanOwner(
        uint256 loanId
    ) external view loanExists(loanId) returns (address) {
        return _loans[loanId].owner;
    }

    /// @notice Gets the Max LTV for a collection, this is the maximum amount of debt that can be taken out against a collection in a borrow operation.
    /// @param collection The address of the collection to get the max collaterization price for.
    /// @return The Max LTV for the collection (10000 = 100%).
    function getCollectionMaxLTV(
        address collection
    ) external view override returns (uint256) {
        if (_collectionsRiskParameters[collection].maxLTV == 0) {
            return _defaultMaxLTV;
        }
        return _collectionsRiskParameters[collection].maxLTV;
    }

    /// @notice Gets the Liquidation Threshold for a collection.
    /// @param collection The address of the collection to get the max collaterization price for.
    /// @return The Liquidation Threshold for the collection (10000 = 100%).
    function getCollectionLiquidationThreshold(
        address collection
    ) public view override returns (uint256) {
        if (_collectionsRiskParameters[collection].maxLTV == 0) {
            return _defaultLiquidationThreshold;
        }
        return _collectionsRiskParameters[collection].liquidationThreshold;
    }

    /// @notice Auxiliary function to close the loan
    /// @param loanId The ID of the loan to close
    function _closeLoan(uint256 loanId) internal {
        // Cache loan NFTs array
        uint256[] memory loanTokenIds = _loans[loanId].nftTokenIds;
        // Get loans nft mapping
        address loanCollection = _loans[loanId].nftAsset;

        // Remove nft to loan id mapping
        for (uint256 i = 0; i < loanTokenIds.length; i++) {
            delete _nftToLoanId[loanCollection][loanTokenIds[i]];
        }

        // Remove loan from user active loans
        address loanOwner = _loans[loanId].owner;
        uint256[] memory userActiveLoans = _activeLoans[loanOwner];
        for (uint256 i = 0; i < userActiveLoans.length; i++) {
            if (userActiveLoans[i] == loanId) {
                _activeLoans[loanOwner][i] = userActiveLoans[
                    userActiveLoans.length - 1
                ];
                _activeLoans[loanOwner].pop();
                break;
            }
        }
    }

    /// @notice GEts the loan interest for a given timestamp
    /// @param loanId The ID of the loan
    /// @param timestamp The timestamp to get the interest for
    /// @return The amount of interest owed on the loan
    function _getLoanInterest(
        uint256 loanId,
        uint256 timestamp
    ) internal view returns (uint256) {
        //Interest increases every 30 minutes
        uint256 incrementalTimestamp = (((timestamp - 1) / (30 * 60)) + 1) *
            (30 * 60);
        DataTypes.LoanData memory loan = _loans[loanId];

        return
            (loan.amount *
                uint256(loan.borrowRate) *
                (incrementalTimestamp - uint256(loan.debtTimestamp))) /
            (PercentageMath.PERCENTAGE_FACTOR * 365 days);
    }

    /// @notice Internal function to get the debt owed on a loan
    /// @param loanId The ID of the loan
    /// @return The total amount of debt owed on the loan
    function _getLoanDebt(uint256 loanId) internal view returns (uint256) {
        return
            _getLoanInterest(loanId, block.timestamp) + _loans[loanId].amount;
    }

    function _requireOnlyMarket() internal view {
        require(
            msg.sender == _addressProvider.getLendingMarket(),
            "LC:NOT_MARKET"
        );
    }

    function _requireLoanExists(uint256 loanId) internal view {
        require(
            _loans[loanId].state != DataTypes.LoanState.None,
            "LC:UNEXISTENT_LOAN"
        );
    }

    function _requireLoanAuctioned(uint256 loanId) internal view {
        require(
            _loans[loanId].state == DataTypes.LoanState.Auctioned,
            "LC:NOT_AUCTIONED"
        );
    }
}
