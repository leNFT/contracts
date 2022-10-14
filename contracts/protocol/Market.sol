// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.8.15;

import {IMarket} from "../interfaces/IMarket.sol";
import {IWETH} from "../interfaces/IWETH.sol";
import {SupplyLogic} from "../libraries/logic/SupplyLogic.sol";
import {LiquidationLogic} from "../libraries/logic/LiquidationLogic.sol";
import {BorrowLogic} from "../libraries/logic/BorrowLogic.sol";
import {DataTypes} from "../libraries/types/DataTypes.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {IAddressesProvider} from "../interfaces/IAddressesProvider.sol";
import {IReserve} from "../interfaces/IReserve.sol";
import {Reserve} from "./Reserve.sol";
import {LoanLogic} from "../libraries/logic/LoanLogic.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import {Trustus} from "./Trustus.sol";
import "hardhat/console.sol";

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
    // collection + asset = reserve
    mapping(address => mapping(address => address)) private _reserves;
    IAddressesProvider private _addressProvider;
    uint256 private _defaultLiquidationPenalty;
    uint256 private _defaultProtocolLiquidationFee;
    uint256 private _defaultMaximumUtilizationRate;
    uint256 private _defaultUnderlyingSafeguard;

    // Initialize the market
    function initialize(
        IAddressesProvider addressesProvider,
        uint256 maximumUtilizationRate,
        uint256 liquidationPenalty,
        uint256 protocolLiquidationFee,
        uint256 underlyingSafeguard
    ) external initializer {
        __Ownable_init();
        _addressProvider = addressesProvider;
        _defaultLiquidationPenalty = liquidationPenalty;
        _defaultProtocolLiquidationFee = protocolLiquidationFee;
        _defaultMaximumUtilizationRate = maximumUtilizationRate;
        _defaultUnderlyingSafeguard = underlyingSafeguard;
    }

    /// @notice Deposit any ERC-20 asset in the reserve
    /// @dev Needs to give approval to the corresponding reserve
    /// @param asset The address of the asset the be deposited
    /// @param amount Amount of the asset to be deposited
    function deposit(
        address collection,
        address asset,
        uint256 amount
    ) external override nonReentrant {
        SupplyLogic.deposit(_reserves, collection, asset, amount);

        emit Deposit(msg.sender, asset, amount);
    }

    /// @notice Deposit ETH in the wETH reserve
    /// @dev Needs to give approval to the corresponding reserve
    function depositETH(address collection)
        external
        payable
        override
        nonReentrant
    {
        address wethAddress = _addressProvider.getWETH();
        IWETH WETH = IWETH(wethAddress);

        // Deposit WETH into the callers account
        WETH.deposit{value: msg.value}();
        WETH.transfer(msg.sender, msg.value);

        SupplyLogic.deposit(_reserves, collection, wethAddress, msg.value);

        emit Deposit(msg.sender, wethAddress, msg.value);
    }

    /// @notice Withdraw an asset from the reserve
    /// @param asset The address of the asset the be withdrawn
    /// @param amount Amount of the asset to be withdrawn
    function withdraw(
        address collection,
        address asset,
        uint256 amount
    ) external override nonReentrant {
        SupplyLogic.withdraw(
            _addressProvider,
            _reserves,
            collection,
            msg.sender,
            asset,
            amount
        );

        emit Withdraw(msg.sender, asset, amount);
    }

    /// @notice Withdraw an asset from the reserve
    /// @param amount Amount of the asset to be withdrawn
    function withdrawETH(address collection, uint256 amount)
        external
        override
        nonReentrant
    {
        address wethAddress = _addressProvider.getWETH();
        IWETH WETH = IWETH(wethAddress);

        SupplyLogic.withdraw(
            _addressProvider,
            _reserves,
            collection,
            address(this),
            wethAddress,
            amount
        );
        WETH.withdraw(amount);

        (bool sent, ) = msg.sender.call{value: amount}("");
        require(sent, "Failed to send Ether");

        emit Withdraw(msg.sender, wethAddress, amount);
    }

    /// @notice Borrow an asset from the reserve while an NFT as collateral
    /// @dev NFT approval needs to be given to the LoanCenter contract
    /// @param amount Amount of the asset to be borrowed
    /// @param nftAddress Address of the NFT collateral
    /// @param nftTokenId Token id of the NFT collateral
    /// @param request ID of the collateral price request sent by the trusted server
    /// @param packet Signed collateral price request sent by the trusted server
    function borrowETH(
        uint256 amount,
        address nftAddress,
        uint256 nftTokenId,
        uint256 genesisNFTId,
        bytes32 request,
        Trustus.TrustusPacket calldata packet
    ) external override nonReentrant {
        address wethAddress = _addressProvider.getWETH();
        IWETH WETH = IWETH(wethAddress);

        BorrowLogic.borrow(
            _addressProvider,
            _reserves,
            address(this),
            wethAddress,
            amount,
            nftAddress,
            nftTokenId,
            genesisNFTId,
            request,
            packet
        );

        WETH.withdraw(amount);

        (bool sent, ) = msg.sender.call{value: amount}("");
        require(sent, "Failed to send Ether");

        emit Borrow(msg.sender, wethAddress, nftAddress, nftTokenId, amount);
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
        uint256 genesisNFTId,
        bytes32 request,
        Trustus.TrustusPacket calldata packet
    ) external override nonReentrant {
        BorrowLogic.borrow(
            _addressProvider,
            _reserves,
            msg.sender,
            asset,
            amount,
            nftAddress,
            nftTokenId,
            genesisNFTId,
            request,
            packet
        );

        emit Borrow(msg.sender, asset, nftAddress, nftTokenId, amount);
    }

    /// @notice Repay an an active loan
    /// @param loanId The ID of the loan to be paid
    function repayETH(uint256 loanId) external payable override nonReentrant {
        address wethAddress = _addressProvider.getWETH();
        IWETH WETH = IWETH(wethAddress);

        // Deposit WETH into the callers account
        WETH.deposit{value: msg.value}();
        WETH.transfer(msg.sender, msg.value);

        BorrowLogic.repay(_addressProvider, loanId, msg.value);

        emit Repay(msg.sender, loanId);
    }

    /// @notice Repay an an active loan
    /// @param loanId The ID of the loan to be paid
    function repay(uint256 loanId, uint256 amount)
        external
        override
        nonReentrant
    {
        BorrowLogic.repay(_addressProvider, loanId, amount);

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

    /// @notice Create a new reserve for a certain collection
    /// @param collection The collection using this reserve
    /// @param asset The address of the asset the reserve controls
    function createReserve(address collection, address asset) external {
        require(
            _reserves[collection][asset] == address(0),
            "Reserve already exists"
        );
        IReserve newReserve = new Reserve(
            _addressProvider,
            owner(),
            asset,
            string.concat("RESERVE", IERC20Metadata(asset).name()),
            string.concat("R", IERC20Metadata(asset).symbol()),
            _defaultMaximumUtilizationRate,
            _defaultLiquidationPenalty,
            _defaultProtocolLiquidationFee,
            _defaultUnderlyingSafeguard
        );

        //Approve reserve use of Market balance
        IERC20(asset).approve(address(newReserve), 2**256 - 1);

        _reserves[collection][asset] = address(newReserve);
    }

    /// @notice Get the reserve address responsible to a certain asset
    /// @param asset The asset the reserve is responsible for
    /// @return The address of the reserve responsible for the asset
    function getReserve(address collection, address asset)
        external
        view
        returns (address)
    {
        return _reserves[collection][asset];
    }

    function setReserve(
        address collection,
        address asset,
        address reserve
    ) external onlyOwner {
        _reserves[collection][asset] = reserve;
    }

    function setDefaultLiquidationPenalty(uint256 liquidationPenalty)
        external
        onlyOwner
    {
        _defaultLiquidationPenalty = liquidationPenalty;
    }

    function setDefaultProtocolLiquidationFee(uint256 protocolLiquidationFee)
        external
        onlyOwner
    {
        _defaultProtocolLiquidationFee = protocolLiquidationFee;
    }

    function setDefaultMaximumUtilizationRate(uint256 maximumUtilizationRate)
        external
        onlyOwner
    {
        _defaultMaximumUtilizationRate = maximumUtilizationRate;
    }

    function setDefaultUnderlyingSafeguard(uint256 underlyingSafeguard)
        external
        onlyOwner
    {
        _defaultUnderlyingSafeguard = underlyingSafeguard;
    }

    function getDefaultLiquidationPenalty() external returns (uint256) {
        return _defaultLiquidationPenalty;
    }

    function getDefaultProtocolLiquidationFee() external returns (uint256) {
        return _defaultProtocolLiquidationFee;
    }

    function getDefaultMaximumUtilizationRate() external returns (uint256) {
        return _defaultMaximumUtilizationRate;
    }

    function getDefaultUnderlyingSafeguard() external returns (uint256) {
        return _defaultUnderlyingSafeguard;
    }

    // Add receive ETH function
    receive() external payable {}
}
