// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.8.19;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {ILoanCenter} from "../../interfaces/ILoanCenter.sol";
import {INFTOracle} from "../../interfaces/INFTOracle.sol";
import {PercentageMath} from "../../libraries/math/PercentageMath.sol";
import {DataTypes} from "../../libraries/types/DataTypes.sol";
import {LoanLogic} from "../../libraries/logic/LoanLogic.sol";
import {ERC721HolderUpgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC721/utils/ERC721HolderUpgradeable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {IERC721Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC721/IERC721Upgradeable.sol";
import {IAddressesProvider} from "../../interfaces/IAddressesProvider.sol";
import {ContextUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ContextUpgradeable.sol";
import {Trustus} from "../../protocol/Trustus/Trustus.sol";

/// @title LoanCenter contract
/// @dev A smart contract managing loans with NFTs as collateral
contract LoanCenter is
    Initializable,
    ContextUpgradeable,
    ILoanCenter,
    ERC721HolderUpgradeable,
    OwnableUpgradeable
{
    // NFT address + NFT ID to loan ID mapping
    mapping(address => mapping(uint256 => uint256)) private _nftToLoanId;

    // Loan ID to loan info mapping
    mapping(uint256 => DataTypes.LoanData) private _loans;

    // Loan id to liquidation data
    mapping(uint256 => DataTypes.LoanLiquidationData)
        private _loansLiquidationData;

    uint256 private _loansCount;
    IAddressesProvider private _addressProvider;

    // Collection to liquidation threshold
    mapping(address => DataTypes.CollectionRiskParameters)
        private _collectionsRiskParameters;

    DataTypes.CollectionRiskParameters _defaultCollectionsRiskParameters;

    // Mapping from address to active loans
    mapping(address => uint256[]) private _activeLoans;

    using LoanLogic for DataTypes.LoanData;

    modifier onlyMarket() {
        _requireOnlyMarket();
        _;
    }

    modifier loanExists(uint256 loanId) {
        _requireLoanExists(loanId);
        _;
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// @notice Initializes the contract
    /// @param addressesProvider The address of the AddressesProvider contract
    /// @param defaultCollectionsRiskParameters The default collection Risk Parameters
    function initialize(
        IAddressesProvider addressesProvider,
        DataTypes.CollectionRiskParameters
            calldata defaultCollectionsRiskParameters
    ) external initializer {
        __Ownable_init();
        __ERC721Holder_init();
        __Context_init();
        _addressProvider = addressesProvider;
        _defaultCollectionsRiskParameters = defaultCollectionsRiskParameters;
    }

    /// @notice Create a new loan with the specified parameters and add it to the loans list
    /// @dev Only the market contract can call this function
    /// @param pool The address of the lending pool
    /// @param amount The amount of the lending pool token to be borrowed
    /// @param genesisNFTId The ID of the first NFT in the collateral
    /// @param nftAddress The address of the NFT contract
    /// @param nftTokenIds An array of NFT token IDs that will be used as collateral
    /// @param borrowRate The interest rate for the loan
    /// @return The ID of the newly created loan
    function createLoan(
        address owner,
        address pool,
        uint256 amount,
        uint256 genesisNFTId,
        address nftAddress,
        uint256[] calldata nftTokenIds,
        uint256 borrowRate
    ) public override onlyMarket returns (uint256) {
        // Create the loan and add it to the list
        _loans[_loansCount].init(
            owner,
            pool,
            amount,
            genesisNFTId,
            nftAddress,
            nftTokenIds,
            borrowRate
        );

        // Add NFT to loanId mapping
        for (uint256 i = 0; i < nftTokenIds.length; i++) {
            _nftToLoanId[nftAddress][nftTokenIds[i]] = _loansCount;
        }

        // Add loan to active loans
        _activeLoans[owner].push(_loansCount);

        // Increment the loans count and then return it
        return _loansCount++;
    }

    /// @notice Activate a loan by setting its state to Active
    /// @dev Only the market contract can call this function
    /// @param loanId The ID of the loan to be activated
    function activateLoan(uint256 loanId) external override onlyMarket {
        // Update loan state
        _loans[loanId].state = DataTypes.LoanState.Active;
    }

    /// @notice Repay a loan by setting its state to Repaid
    /// @dev Only the market contract can call this function
    /// @param loanId The ID of the loan to be repaid
    function repayLoan(uint256 loanId) external override onlyMarket {
        // Update loan state
        _loans[loanId].state = DataTypes.LoanState.Repaid;
        // Cache loan NFTs array
        uint256[] memory loanTokenIds = _loans[loanId].nftTokenIds;
        // Get loans nft mapping
        address loanCollection = _loans[loanId].nftAsset;

        // Remove nft to loan id mapping
        for (uint256 i = 0; i < loanTokenIds.length; i++) {
            delete _nftToLoanId[loanCollection][loanTokenIds[i]];
        }

        // Remove loan from user active loans
        uint256[] memory userActiveLoans = _activeLoans[_loans[loanId].owner];
        for (uint256 i = 0; i < userActiveLoans.length; i++) {
            if (userActiveLoans[i] == loanId) {
                _activeLoans[_loans[loanId].owner][i] = userActiveLoans[
                    userActiveLoans.length - 1
                ];
                _activeLoans[_loans[loanId].owner].pop();
                break;
            }
        }
    }

    /// @notice Liquidate a loan by setting its state to Liquidated and freeing up the NFT collateral pointers
    /// @dev Only the market contract can call this function
    /// @param loanId The ID of the loan to be liquidated
    function liquidateLoan(uint256 loanId) external override onlyMarket {
        // Update state
        _loans[loanId].state = DataTypes.LoanState.Liquidated;
        // Cache loan NFTs array
        uint256[] memory loanTokenIds = _loans[loanId].nftTokenIds;
        // Get loans nft mapping
        address loanCollection = _loans[loanId].nftAsset;

        for (uint256 i = 0; i < loanTokenIds.length; i++) {
            delete _nftToLoanId[loanCollection][loanTokenIds[i]];
        }

        // Remove loan from user active loans
        uint256[] memory userActiveLoans = _activeLoans[_loans[loanId].owner];
        for (uint256 i = 0; i < userActiveLoans.length; i++) {
            if (userActiveLoans[i] == loanId) {
                _activeLoans[_loans[loanId].owner][i] = userActiveLoans[
                    userActiveLoans.length - 1
                ];
                _activeLoans[_loans[loanId].owner].pop();
                break;
            }
        }
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
            auctioner: user,
            liquidator: user,
            auctionStartTimestamp: uint40(block.timestamp),
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
        returns (DataTypes.LoanLiquidationData memory)
    {
        return _loansLiquidationData[loanId];
    }

    /// @notice Get the maximum debt a loan can reach before entering the liquidation zone
    /// @param loanId The ID of the loan to be queried
    /// @param tokensPrice The price of the tokens collateralizing the loan
    /// @return The maximum debt quoted in the same asset as the price of the collateral tokens
    function getLoanMaxDebt(
        uint256 loanId,
        uint256 tokensPrice
    ) external view override loanExists(loanId) returns (uint256) {
        return
            PercentageMath.percentMul(
                tokensPrice,
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

    /// @notice Internal function to get the debt owed on a loan
    /// @param loanId The ID of the loan
    /// @return The total amount of debt owed on the loan
    function _getLoanDebt(uint256 loanId) internal view returns (uint256) {
        return
            _loans[loanId].getInterest(block.timestamp) + _loans[loanId].amount;
    }

    /// @notice Get the debt owed on a loan
    /// @param loanId The ID of the loan
    /// @return The total amount of debt owed on the loan quoted in the same asset of the loan's lending pool
    function getLoanDebt(
        uint256 loanId
    ) public view override loanExists(loanId) returns (uint256) {
        return _getLoanDebt(loanId);
    }

    /// @notice Get the interest owed on a loan
    /// @param loanId The ID of the loan
    /// @return The amount of interest owed on the loan
    function getLoanInterest(
        uint256 loanId
    ) external view override loanExists(loanId) returns (uint256) {
        return _loans[loanId].getInterest(block.timestamp);
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
    ) external view returns (DataTypes.LoanState) {
        return _loans[loanId].state;
    }

    /// @notice Get the owner of a loan
    /// @param loanId The ID of the loan
    /// @return The address of the owner of the loan
    function getLoanOwner(
        uint256 loanId
    ) external view loanExists(loanId) returns (address) {
        return _loans[loanId].owner;
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

    /// @notice Gets the Liquidation Threshold for a collection.
    /// @param collection The address of the collection to get the max collaterization price for.
    /// @return The Liquidation Threshold for the collection (10000 = 100%).
    function getCollectionLiquidationThreshold(
        address collection
    ) public view override returns (uint256) {
        if (_collectionsRiskParameters[collection].maxLTV == 0) {
            return _defaultCollectionsRiskParameters.liquidationThreshold;
        }
        return _collectionsRiskParameters[collection].liquidationThreshold;
    }

    /// @notice Gets the Max LTV for a collection.
    /// @param collection The address of the collection to get the max collaterization price for.
    /// @return The Max LTV for the collection (10000 = 100%).
    function getCollectionMaxLTV(
        address collection
    ) external view override returns (uint256) {
        if (_collectionsRiskParameters[collection].maxLTV == 0) {
            return _defaultCollectionsRiskParameters.maxLTV;
        }
        return _collectionsRiskParameters[collection].maxLTV;
    }

    /// @notice Changes the Risk Parameters for a collection.
    /// @param collection The address of the collection to change the max collaterization price for.
    /// @param liquidationThreshold The new liquidation Threshold to set (10000 = 100%).
    function setCollectionRiskParameters(
        address collection,
        uint256 maxLTV,
        uint256 liquidationThreshold
    ) external onlyOwner {
        //Set the max collaterization
        _collectionsRiskParameters[collection] = DataTypes
            .CollectionRiskParameters({
                maxLTV: uint16(maxLTV),
                liquidationThreshold: uint16(liquidationThreshold)
            });
    }

    /// @notice Approves a lending market to use all NFTs from a collection.
    /// @param collection The address of the collection to approve for lending.
    function approveNFTCollection(
        address collection
    ) external override onlyMarket {
        IERC721Upgradeable(collection).setApprovalForAll(
            _addressProvider.getLendingMarket(),
            true
        );
    }

    function _requireOnlyMarket() internal view {
        require(
            _msgSender() == _addressProvider.getLendingMarket(),
            "Caller must be Market contract"
        );
    }

    function _requireLoanExists(uint256 loanId) internal view {
        require(
            _loans[loanId].state != DataTypes.LoanState.None,
            "Loan does not exist."
        );
    }
}
