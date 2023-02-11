// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.8.17;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {ILoanCenter} from "../../interfaces/ILoanCenter.sol";
import {INFTOracle} from "../../interfaces/INFTOracle.sol";
import {PercentageMath} from "../../libraries/math/PercentageMath.sol";
import {ITokenOracle} from "../../interfaces/ITokenOracle.sol";
import {ILendingPool} from "../../interfaces/ILendingPool.sol";
import {DataTypes} from "../../libraries/types/DataTypes.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {LoanLogic} from "../../libraries/logic/LoanLogic.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {IERC721Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC721/IERC721Upgradeable.sol";
import {IERC721ReceiverUpgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC721/IERC721ReceiverUpgradeable.sol";
import {IAddressesProvider} from "../../interfaces/IAddressesProvider.sol";
import {ContextUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ContextUpgradeable.sol";
import {Trustus} from "../../protocol/Trustus/Trustus.sol";
import "hardhat/console.sol";

contract LoanCenter is
    Initializable,
    ContextUpgradeable,
    ILoanCenter,
    IERC721ReceiverUpgradeable,
    OwnableUpgradeable
{
    // NFT address + NFT ID to loan ID mapping
    mapping(address => mapping(uint256 => uint256)) private _nftToLoanId;

    // Loan ID to loan info mapping
    mapping(uint256 => DataTypes.LoanData) private _loans;
    uint256 private _loansCount;
    IAddressesProvider private _addressProvider;

    // Collection to number of active loans
    mapping(address => mapping(address => uint256)) private _activeLoansCount;

    // Collection to max collaterization
    mapping(address => uint256) private _collectionsMaxCollaterization;
    uint256 _defaultMaxCollaterization;

    using LoanLogic for DataTypes.LoanData;

    modifier onlyMarket() {
        require(
            _msgSender() == _addressProvider.getLendingMarket(),
            "Caller must be Market contract"
        );
        _;
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    // Initialize the loancenter
    function initialize(
        IAddressesProvider addressesProvider,
        uint256 maxCollaterization
    ) external initializer {
        __Ownable_init();
        _addressProvider = addressesProvider;
        _defaultMaxCollaterization = maxCollaterization;
    }

    function createLoan(
        address borrower,
        address reserve,
        uint256 amount,
        uint256 maxLTV,
        uint256 boost,
        uint256 genesisNFTId,
        address nftAddress,
        uint256[] memory nftTokenIds,
        uint256 borrowRate
    ) public override onlyMarket returns (uint256) {
        // Create the loan and add it to the list
        _loans[_loansCount].init(
            _loansCount,
            borrower,
            reserve,
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

        _loansCount++;

        return _loansCount - 1;
    }

    function activateLoan(uint256 loanId) external override onlyMarket {
        // Must use storage to update state
        DataTypes.LoanData storage loan = _loans[loanId];
        loan.state = DataTypes.LoanState.Active;

        _activeLoansCount[loan.borrower][loan.nftAsset]++;
    }

    function repayLoan(uint256 loanId) external override onlyMarket {
        // Must use storage to update state
        DataTypes.LoanData storage loan = _loans[loanId];
        loan.state = DataTypes.LoanState.Repaid;

        for (uint256 i = 0; i < loan.nftTokenIds.length; i++) {
            _nftToLoanId[loan.nftAsset][loan.nftTokenIds[i]] = 0;
        }

        _activeLoansCount[loan.borrower][loan.nftAsset]--;
    }

    function liquidateLoan(uint256 loanId) external override onlyMarket {
        // Must use storage to update state
        DataTypes.LoanData storage loan = _loans[loanId];
        loan.state = DataTypes.LoanState.Defaulted;

        for (uint256 i = 0; i < loan.nftTokenIds.length; i++) {
            _nftToLoanId[loan.nftAsset][loan.nftTokenIds[i]] = 0;
        }
        _activeLoansCount[loan.borrower][loan.nftAsset]--;
    }

    function getLoansCount() external view override returns (uint256) {
        return _loansCount;
    }

    function getActiveLoansCount(
        address user,
        address collection
    ) external view override returns (uint256) {
        return _activeLoansCount[user][collection];
    }

    function getLoan(
        uint256 loanId
    ) external view override returns (DataTypes.LoanData memory) {
        require(
            _loans[loanId].state != DataTypes.LoanState.None,
            "Loan does not exist."
        );

        return _loans[loanId];
    }

    // Get the max collaterization for a certain collection and a certain user (includes boost) in ETH
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

        return
            PercentageMath.percentMul(
                tokensPrice,
                _loans[loanId].maxLTV + _loans[loanId].boost
            );
    }

    /// @notice Get the price a liquidator would have to pay to liquidate a loan and the rewards associated
    /// @param loanId The ID of the loan to be liquidated
    /// @return price The price of the liquidation in borrowed asset token
    function getLoanLiquidationPrice(
        uint256 loanId,
        bytes32 request,
        Trustus.TrustusPacket calldata packet
    ) external view override returns (uint256) {
        // Get the price of the collateral asset in the reserve asset. Ex: Punk #42 = 5 USDC
        uint256 poolAssetETHPrice = ITokenOracle(
            _addressProvider.getTokenOracle()
        ).getTokenETHPrice(IERC4626(_loans[loanId].pool).asset());

        uint256 collateralETHPrice = (INFTOracle(
            _addressProvider.getNFTOracle()
        ).getTokensETHPrice(
                _loans[loanId].nftAsset,
                _loans[loanId].nftTokenIds,
                request,
                packet
            ) *
            ITokenOracle(_addressProvider.getTokenOracle())
                .getPricePrecision()) / poolAssetETHPrice;

        // Threshold in which the liquidation price starts being equal to debt
        uint256 liquidationThreshold = PercentageMath.percentMul(
            collateralETHPrice,
            PercentageMath.PERCENTAGE_FACTOR -
                ILendingPool(_loans[loanId].pool)
                    .getPoolConfig()
                    .liquidationPenalty +
                ILendingPool(_loans[loanId].pool).getPoolConfig().liquidationFee
        );
        uint256 loanDebt = _getLoanDebt(loanId);
        console.log("liquidationThreshold", liquidationThreshold);
        console.log("loanDebt", loanDebt);

        // Find the cost of liquidation
        uint256 liquidationPrice;
        if (loanDebt < liquidationThreshold) {
            liquidationPrice = liquidationThreshold;
        } else {
            liquidationPrice = loanDebt;
        }

        console.log("liquidationPrice", liquidationPrice);

        return (liquidationPrice);
    }

    function getNFTLoanId(
        address nftAddress,
        uint256 nftTokenId
    ) external view override returns (uint256) {
        return _nftToLoanId[nftAddress][nftTokenId];
    }

    function _getLoanDebt(uint256 loanId) internal view returns (uint256) {
        return
            _loans[loanId].getInterest(block.timestamp) + _loans[loanId].amount;
    }

    function getLoanDebt(
        uint256 loanId
    ) public view override returns (uint256) {
        require(
            _loans[loanId].state != DataTypes.LoanState.None,
            "Loan does not exist."
        );

        return _getLoanDebt(loanId);
    }

    function getLoanInterest(
        uint256 loanId
    ) external view override returns (uint256) {
        require(
            _loans[loanId].state != DataTypes.LoanState.None,
            "Loan does not exist."
        );

        return _loans[loanId].getInterest(block.timestamp);
    }

    function getLoanTokenIds(
        uint256 loanId
    ) external view override returns (uint256[] memory) {
        require(
            _loans[loanId].state != DataTypes.LoanState.None,
            "Loan does not exist."
        );

        return _loans[loanId].nftTokenIds;
    }

    function getLoanTokenAddress(
        uint256 loanId
    ) external view override returns (address) {
        require(
            _loans[loanId].state != DataTypes.LoanState.None,
            "Loan does not exist."
        );

        return _loans[loanId].nftAsset;
    }

    function getLoanLendingPool(
        uint256 loanId
    ) external view override returns (address) {
        require(
            _loans[loanId].state != DataTypes.LoanState.None,
            "Loan does not exist."
        );

        return _loans[loanId].pool;
    }

    function updateLoanDebtTimestamp(
        uint256 loanId,
        uint256 newDebtTimestamp
    ) external override onlyMarket {
        require(
            _loans[loanId].state != DataTypes.LoanState.None,
            "Loan does not exist."
        );

        _loans[loanId].debtTimestamp = newDebtTimestamp;
    }

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

    function getLoanBoost(
        uint256 loanId
    ) external view override returns (uint256) {
        require(
            _loans[loanId].state != DataTypes.LoanState.None,
            "Loan does not exist."
        );

        return _loans[loanId].boost + _loans[loanId].genesisNFTBoost;
    }

    // Get the max collaterization price for a collection (10000 = 100%)
    function getCollectionMaxCollaterization(
        address collection
    ) external view override returns (uint256) {
        if (_collectionsMaxCollaterization[collection] == 0) {
            return _defaultMaxCollaterization;
        }
        return _collectionsMaxCollaterization[collection];
    }

    function changeCollectionMaxCollaterization(
        address collection,
        uint256 maxCollaterization
    ) external override onlyOwner {
        //Set the max collaterization
        _collectionsMaxCollaterization[collection] = maxCollaterization;
    }

    function onERC721Received(
        address,
        address,
        uint256,
        bytes calldata
    ) public pure override returns (bytes4) {
        return
            bytes4(
                keccak256("onERC721Received(address,address,uint256,bytes)")
            );
    }

    function approveNFTCollection(
        address collection
    ) external override onlyMarket {
        IERC721Upgradeable(collection).setApprovalForAll(
            _addressProvider.getLendingMarket(),
            true
        );
    }
}
