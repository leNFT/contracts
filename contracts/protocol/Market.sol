// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.8.15;

import {IMarket} from "../interfaces/IMarket.sol";
import {SupplyLogic} from "../libraries/logic/SupplyLogic.sol";
import {LiquidationLogic} from "../libraries/logic/LiquidationLogic.sol";
import {BorrowLogic} from "../libraries/logic/BorrowLogic.sol";
import {DataTypes} from "../libraries/types/DataTypes.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {IAddressesProvider} from "../interfaces/IAddressesProvider.sol";
import {LoanLogic} from "../libraries/logic/LoanLogic.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import {Trustus} from "./Trustus.sol";

/// @title Market Contract
/// @author leNFT
/// @notice This contract is the entrypoint for the leNFT protocol
/// @dev Call these contrcact functions to interact with the protocol
contract Market is
    Initializable,
    IMarket,
    OwnableUpgradeable,
    ReentrancyGuardUpgradeable
{
    mapping(address => address) private _reserves;
    IAddressesProvider private _addressProvider;

    // Initialize the market
    function initialize(IAddressesProvider addressesProvider)
        external
        initializer
    {
        __Ownable_init();
        _addressProvider = addressesProvider;
    }

    /// @notice Deposit an asset in the reserve
    /// @dev Needs to give approval to the corresponding reserve
    /// @param asset The address of the asset the be deposited
    /// @param amount Amount of the asset to be deposited
    function deposit(address asset, uint256 amount)
        external
        override
        nonReentrant
    {
        SupplyLogic.deposit(_reserves, asset, amount);

        emit Deposit(msg.sender, asset, amount);
    }

    /// @notice Withdraw an asset from the reserve
    /// @param asset The address of the asset the be withdrawn
    /// @param amount Amount of the asset to be withdrawn
    function withdraw(address asset, uint256 amount)
        external
        override
        nonReentrant
    {
        SupplyLogic.withdraw(_addressProvider, _reserves, asset, amount);

        emit Withdraw(msg.sender, asset, amount);
    }

    /// @notice Borrow an asset from the reserve while an NFT as collateral
    /// @dev NFT approval needs to be given to the LoanCenter contract
    /// @param asset The address of the asset the be borrowed
    /// @param amount Amount of the asset to be borrowed
    /// @param nftAddress Address of the NFT collateral
    /// @param nftTokenId Token id of the NFT collateral
    /// @param request ID of the collateral price request sent by the trusted server
    /// @param packet Signed collateral price request sent by the trusted server
    function borrow(
        address asset,
        uint256 amount,
        address nftAddress,
        uint256 nftTokenId,
        uint256 chargeNFTId,
        bytes32 request,
        Trustus.TrustusPacket calldata packet
    ) external override nonReentrant {
        BorrowLogic.borrow(
            _addressProvider,
            _reserves,
            asset,
            amount,
            nftAddress,
            nftTokenId,
            chargeNFTId,
            request,
            packet
        );

        emit Borrow(msg.sender, asset, nftAddress, nftTokenId, amount);
    }

    /// @notice Repay an an active loan
    /// @param loanId The ID of the loan to be paid
    function repay(uint256 loanId) external override nonReentrant {
        BorrowLogic.repay(_addressProvider, loanId);

        emit Repay(msg.sender, loanId);
    }

    /// @notice Liquidate an active loan
    /// @dev Needs to approve WETH transfers from Market address
    /// @param loanId The ID of the loan to be paid
    /// @param request ID of the collateral price request sent by the trusted server
    /// @param packet Signed collateral price request sent by the trusted server
    function liquidate(
        uint256 loanId,
        bytes32 request,
        Trustus.TrustusPacket calldata packet
    ) external override nonReentrant {
        LiquidationLogic.liquidate(_addressProvider, loanId, request, packet);

        emit Liquidate(msg.sender, loanId);
    }

    /// @notice Add a new reserve to the list of reserves
    /// @param asset The address of the asset the reserve controls
    /// @param reserveAddress The address of the reserve
    function addReserve(address asset, address reserveAddress)
        external
        onlyOwner
    {
        //Approve reserve use of Market balance
        IERC20(asset).approve(reserveAddress, 2**256 - 1);

        _reserves[asset] = reserveAddress;
    }

    /// @notice Get the reserve address responsible to a certain asset
    /// @param asset The asset the reserve is responsible for
    /// @return The address of the reserve responsible for the asset
    function getReserveAddress(address asset) external view returns (address) {
        return _reserves[asset];
    }

    /// @notice Check if a certain asset is supported by the protocol as a borrowable asset
    /// @dev An asset is supported by the protocol if a reserve exists responsible for it
    /// @param asset The address of the asset
    /// @return A boolean, true if the asset is supported
    function isAssetSupported(address asset) external view returns (bool) {
        return _reserves[asset] != address(0);
    }
}
