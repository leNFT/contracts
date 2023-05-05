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

    // Collection to number of active loans
    mapping(address => mapping(address => uint256)) private _activeLoansCount;

    // Collection to max collaterization
    mapping(address => uint256) private _collectionsMaxCollaterization;
    uint256 _defaultMaxCollaterization;

    using LoanLogic for DataTypes.LoanData;

    modifier onlyMarket() {
        _requireOnlyMarket();
        _;
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// @notice Initializes the contract
    /// @param addressesProvider The address of the AddressesProvider contract
    /// @param maxCollaterization The default maximum collaterization value to use for new loans
    function initialize(
        IAddressesProvider addressesProvider,
        uint256 maxCollaterization
    ) external initializer {
        __Ownable_init();
        __ERC721Holder_init();
        __Context_init();
        _addressProvider = addressesProvider;
        _defaultMaxCollaterization = maxCollaterization;
    }

    /// @notice Create a new loan with the specified parameters and add it to the loans list
    /// @dev Only the market contract can call this function
    /// @param pool The address of the lending pool
    /// @param amount The amount of the lending pool token to be borrowed
    /// @param maxLTV The maximum loan-to-value ratio
    /// @param boost The boost factor to be applied to the LTV ratio
    /// @param genesisNFTId The ID of the first NFT in the collateral
    /// @param nftAddress The address of the NFT contract
    /// @param nftTokenIds An array of NFT token IDs that will be used as collateral
    /// @param borrowRate The interest rate for the loan
    /// @return The ID of the newly created loan
    function createLoan(
        address pool,
        uint256 amount,
        uint256 maxLTV,
        uint256 boost,
        uint256 genesisNFTId,
        address nftAddress,
        uint256[] calldata nftTokenIds,
        uint256 borrowRate
    ) public override onlyMarket returns (uint256) {
        // Create the loan and add it to the list
        _loans[_loansCount].init(
            pool,
            amount,
            maxLTV,
            boost,
            genesisNFTId,
            nftAddress,
            nftTokenIds,
            borrowRate
        );

        // Add NFT to loanId mapping
        for (uint256 i = 0; i < nftTokenIds.length; i++) {
            _nftToLoanId[nftAddress][nftTokenIds[i]] = _loansCount;
        }

        // Increment the loans count
        return _loansCount++;
    }

    /// @notice Activate a loan by setting its state to Active
    /// @dev Only the market contract can call this function
    /// @param loanId The ID of the loan to be activated
    function activateLoan(uint256 loanId) external override onlyMarket {
        // Must use storage to update state
        DataTypes.LoanData storage loan = _loans[loanId];
        loan.state = DataTypes.LoanState.Active;

        _activeLoansCount[
            IERC721Upgradeable(_addressProvider.getDebtToken()).ownerOf(loanId)
        ][loan.nftAsset]++;
    }

    /// @notice Repay a loan by setting its state to Repaid
    /// @dev Only the market contract can call this function
    /// @param loanId The ID of the loan to be repaid
    function repayLoan(uint256 loanId) external override onlyMarket {
        // Must use storage to update state
        DataTypes.LoanData storage loan = _loans[loanId];
        loan.state = DataTypes.LoanState.Repaid;

        uint256 nftIdsLength = loan.nftTokenIds.length;
        address nftAsset = loan.nftAsset;
        for (uint256 i = 0; i < nftIdsLength; i++) {
            delete _nftToLoanId[nftAsset][loan.nftTokenIds[i]];
        }

        _activeLoansCount[
            IERC721Upgradeable(_addressProvider.getDebtToken()).ownerOf(loanId)
        ][nftAsset]--;
    }

    /// @notice Liquidate a loan by setting its state to Defaulted and freeing up the NFT collateral
    /// @dev Only the market contract can call this function
    /// @param loanId The ID of the loan to be liquidated
    function liquidateLoan(uint256 loanId) external override onlyMarket {
        // Must use storage to update state
        DataTypes.LoanData storage loan = _loans[loanId];
        loan.state = DataTypes.LoanState.Liquidated;

        uint256 nftIdsLength = loan.nftTokenIds.length;
        address nftAsset = loan.nftAsset;
        for (uint256 i = 0; i < nftIdsLength; i++) {
            delete _nftToLoanId[nftAsset][loan.nftTokenIds[i]];
        }
        _activeLoansCount[
            IERC721Upgradeable(_addressProvider.getDebtToken()).ownerOf(loanId)
        ][nftAsset]--;
    }

    function auctionLoan(
        uint256 loanId,
        address user,
        uint256 bid
    ) external override onlyMarket {
        DataTypes.LoanData storage loan = _loans[loanId];
        loan.state = DataTypes.LoanState.Auctioned;

        // Create the liquidation data
        _loansLiquidationData[loanId] = DataTypes.LoanLiquidationData({
            auctioner: user,
            liquidator: user,
            auctionStartTimestamp: uint40(block.timestamp),
            auctionMaxBid: bid
        });
    }

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

    /// @notice Get the number of active loans for a user and an NFT collection
    /// @param user The address of the user
    /// @param collection The address of the NFT collection
    /// @return The number of active loans
    function getActiveLoansCount(
        address user,
        address collection
    ) external view override returns (uint256) {
        return _activeLoansCount[user][collection];
    }

    /// @notice Get a loan by its ID
    /// @param loanId The ID of the loan to be retrieved
    /// @return The loan data
    function getLoan(
        uint256 loanId
    ) external view override returns (DataTypes.LoanData memory) {
        require(
            _loans[loanId].state != DataTypes.LoanState.None,
            "Loan does not exist."
        );

        return _loans[loanId];
    }

    function getLoanLiquidationData(
        uint256 loanId
    ) external view override returns (DataTypes.LoanLiquidationData memory) {
        require(
            _loans[loanId].state == DataTypes.LoanState.Auctioned,
            "Loan is not being auctioned."
        );

        return _loansLiquidationData[loanId];
    }

    /// @notice Get the maximum collateral that can be put up for a loan in ETH
    /// @param loanId The ID of the loan to be queried
    /// @param request The Trustus request hash
    /// @param packet The Trustus packet
    /// @return The maximum collateral in ETH
    function getLoanMaxETHCollateral(
        uint256 loanId,
        bytes32 request,
        Trustus.TrustusPacket calldata packet
    ) external view override returns (uint256) {
        require(
            _loans[loanId].state != DataTypes.LoanState.None,
            "Loan does not exist."
        );

        uint256 tokensPrice = INFTOracle(_addressProvider.getNFTOracle())
            .getTokensETHPrice(
                _loans[loanId].nftAsset,
                _loans[loanId].nftTokenIds,
                request,
                packet
            );

        return PercentageMath.percentMul(tokensPrice, _loans[loanId].maxLTV);
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
    /// @return The total amount of debt owed on the loan
    function getLoanDebt(
        uint256 loanId
    ) public view override returns (uint256) {
        require(
            _loans[loanId].state != DataTypes.LoanState.None,
            "Loan does not exist."
        );

        return _getLoanDebt(loanId);
    }

    /// @notice Get the interest owed on a loan
    /// @param loanId The ID of the loan
    /// @return The amount of interest owed on the loan
    function getLoanInterest(
        uint256 loanId
    ) external view override returns (uint256) {
        require(
            _loans[loanId].state != DataTypes.LoanState.None,
            "Loan does not exist."
        );

        return _loans[loanId].getInterest(block.timestamp);
    }

    /// @notice Get the NFT token IDs associated with a loan
    /// @param loanId The ID of the loan
    /// @return An array of the NFT token IDs associated with the loan
    function getLoanTokenIds(
        uint256 loanId
    ) external view override returns (uint256[] memory) {
        require(
            _loans[loanId].state != DataTypes.LoanState.None,
            "Loan does not exist."
        );

        return _loans[loanId].nftTokenIds;
    }

    /// @notice Get the NFT contract address associated with a loan
    /// @param loanId The ID of the loan
    /// @return The address of the NFT contract associated with the loan
    function getLoanTokenAddress(
        uint256 loanId
    ) external view override returns (address) {
        require(
            _loans[loanId].state != DataTypes.LoanState.None,
            "Loan does not exist."
        );

        return _loans[loanId].nftAsset;
    }

    /// @notice Get the lending pool address associated with a loan
    /// @param loanId The ID of the loan
    /// @return The address of the lending pool associated with the loan
    function getLoanLendingPool(
        uint256 loanId
    ) external view override returns (address) {
        require(
            _loans[loanId].state != DataTypes.LoanState.None,
            "Loan does not exist."
        );

        return _loans[loanId].pool;
    }

    /// @notice Updates the debt timestamp of a loan.
    /// @param loanId The ID of the loan to update.
    /// @param newDebtTimestamp The new debt timestamp to set.
    function updateLoanDebtTimestamp(
        uint256 loanId,
        uint256 newDebtTimestamp
    ) external override onlyMarket {
        require(
            _loans[loanId].state != DataTypes.LoanState.None,
            "Loan does not exist."
        );

        _loans[loanId].debtTimestamp = uint40(newDebtTimestamp);
    }

    /// @notice Updates the amount of a loan.
    /// @param loanId The ID of the loan to update.
    /// @param newAmount The new amount to set.
    function updateLoanAmount(
        uint256 loanId,
        uint256 newAmount
    ) external override onlyMarket {
        require(
            _loans[loanId].state != DataTypes.LoanState.None,
            "Loan does not exist."
        );

        _loans[loanId].amount = newAmount;
    }

    /// @notice Gets the max collaterization price for a collection.
    /// @param collection The address of the collection to get the max collaterization price for.
    /// @return The max collaterization price for the collection (10000 = 100%).
    function getCollectionMaxCollaterization(
        address collection
    ) external view override returns (uint256) {
        if (_collectionsMaxCollaterization[collection] == 0) {
            return _defaultMaxCollaterization;
        }
        return _collectionsMaxCollaterization[collection];
    }

    /// @notice Changes the max collaterization price for a collection.
    /// @param collection The address of the collection to change the max collaterization price for.
    /// @param maxCollaterization The new max collaterization price to set (10000 = 100%).
    function changeCollectionMaxCollaterization(
        address collection,
        uint256 maxCollaterization
    ) external override onlyOwner {
        //Set the max collaterization
        _collectionsMaxCollaterization[collection] = maxCollaterization;
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
}
