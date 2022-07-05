// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.8.15;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {ILoanCenter} from "../interfaces/ILoanCenter.sol";
import {PercentageMath} from "../libraries/math/PercentageMath.sol";
import {DataTypes} from "../libraries/types/DataTypes.sol";
import {LoanLogic} from "../libraries/logic/LoanLogic.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {IERC721Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC721/IERC721Upgradeable.sol";
import {IERC721ReceiverUpgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC721/IERC721ReceiverUpgradeable.sol";
import {IMarketAddressesProvider} from "../interfaces/IMarketAddressesProvider.sol";

contract LoanCenter is
    Initializable,
    ILoanCenter,
    IERC721ReceiverUpgradeable,
    OwnableUpgradeable
{
    // NFT address + NFT ID to loan ID mapping
    mapping(address => mapping(uint256 => uint256)) private _nftToLoanId;

    // Loan ID to loan info mapping
    mapping(uint256 => DataTypes.LoanData) private _loans;
    uint256 private _loansCount;
    IMarketAddressesProvider private _addressesProvider;

    using LoanLogic for DataTypes.LoanData;

    modifier onlyMarket() {
        require(
            _msgSender() == address(_addressesProvider.getMarketAddress()),
            "Caller must be Market contract"
        );
        _;
    }

    // Initialize the loancenter
    function initialize(IMarketAddressesProvider addressesProvider)
        external
        initializer
    {
        __Ownable_init();
        _addressesProvider = addressesProvider;
    }

    function createLoan(
        address borrower,
        address asset,
        uint256 amount,
        address nftAddress,
        uint256 nftTokenID,
        uint256 borrowRate
    ) external override onlyMarket returns (uint256) {
        // Create the loan and add it to the list
        _loans[_loansCount].init(
            _loansCount,
            borrower,
            asset,
            amount,
            nftAddress,
            nftTokenID,
            borrowRate
        );

        // Add NFT to loanId mapping
        _nftToLoanId[nftAddress][nftTokenID] = _loansCount;

        _loansCount++;

        return _loansCount - 1;
    }

    function activateLoan(uint256 loanId) external override onlyMarket {
        // Must use storage to update state
        DataTypes.LoanData storage loan = _loans[loanId];
        loan.state = DataTypes.LoanState.Active;
    }

    function repayLoan(uint256 loanId) external override onlyMarket {
        // Must use storage to update state
        DataTypes.LoanData storage loan = _loans[loanId];
        loan.state = DataTypes.LoanState.Repaid;

        _nftToLoanId[loan.nftAsset][loan.nftTokenId] = 0;
    }

    function liquidateLoan(uint256 loanId) external override onlyMarket {
        // Must use storage to update state
        DataTypes.LoanData storage loan = _loans[loanId];
        loan.state = DataTypes.LoanState.Defaulted;

        _nftToLoanId[loan.nftAsset][loan.nftTokenId] = 0;
    }

    function getLoansCount() external view override returns (uint256) {
        return _loansCount;
    }

    function getLoan(uint256 loanId)
        external
        view
        override
        returns (DataTypes.LoanData memory)
    {
        return _loans[loanId];
    }

    function getNFTLoan(address nftAddress, uint256 nftTokenID)
        external
        view
        override
        returns (uint256)
    {
        return _nftToLoanId[nftAddress][nftTokenID];
    }

    function getLoanDebt(uint256 loanId)
        external
        view
        override
        returns (uint256)
    {
        return
            _loans[loanId].getInterest(block.timestamp) + _loans[loanId].amount;
    }

    function getLoanInterest(uint256 loanId)
        external
        view
        override
        returns (uint256)
    {
        return _loans[loanId].getInterest(block.timestamp);
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

    function approveNFTCollection(address collection) external onlyOwner {
        IERC721Upgradeable(collection).setApprovalForAll(
            _addressesProvider.getMarketAddress(),
            true
        );
    }
}
