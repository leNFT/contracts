// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.8.17;

import {IMarket} from "../interfaces/IMarket.sol";
import {ITokenOracle} from "../interfaces/ITokenOracle.sol";
import {IWETH} from "../interfaces/IWETH.sol";
import {SupplyLogic} from "../libraries/logic/SupplyLogic.sol";
import {LiquidationLogic} from "../libraries/logic/LiquidationLogic.sol";
import {BorrowLogic} from "../libraries/logic/BorrowLogic.sol";
import {DataTypes} from "../libraries/types/DataTypes.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {IAddressesProvider} from "../interfaces/IAddressesProvider.sol";
import {ILoanCenter} from "../interfaces/ILoanCenter.sol";
import {IReserve} from "../interfaces/IReserve.sol";
import {Reserve} from "./Reserve.sol";
import {LoanLogic} from "../libraries/logic/LoanLogic.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {ERC165Checker} from "@openzeppelin/contracts/utils/introspection/ERC165Checker.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import {Trustus} from "./Trustus/Trustus.sol";
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
    using ERC165Checker for address;

    // collection + asset = reserve
    mapping(address => mapping(address => address)) private _reserves;
    // reserve = valid (bool)
    mapping(address => bool) private _validReserves;

    IAddressesProvider private _addressProvider;
    uint256 private _defaultLiquidationPenalty;
    uint256 private _defaultProtocolLiquidationFee;
    uint256 private _defaultMaximumUtilizationRate;
    uint256 private _defaultUnderlyingSafeguard;

    // Initialize the market
    function initialize(
        IAddressesProvider addressesProvider,
        uint256 liquidationPenalty,
        uint256 protocolLiquidationFee,
        uint256 maximumUtilizationRate,
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
    /// @param reserve The address of the reserve we are depositing into
    /// @param amount Amount of the asset to be depositedreserve
    function deposit(address reserve, uint256 amount)
        external
        override
        nonReentrant
    {
        require(_validReserves[reserve] == true, "Invalid Reserve");
        SupplyLogic.deposit(
            DataTypes.DepositParams({reserve: reserve, amount: amount})
        );

        emit Deposit(msg.sender, reserve, amount);
    }

    /// @notice Deposit ETH in the wETH reserve
    /// @dev Needs to give approval to the corresponding reserve
    function depositETH(address reserve)
        external
        payable
        override
        nonReentrant
    {
        address wethAddress = _addressProvider.getWETH();

        require(_validReserves[reserve] == true, "Invalid Reserve");
        require(
            IReserve(reserve).getAsset() == wethAddress,
            "Reserve underlying is not WETH"
        );

        // Deposit WETH into the callers account
        IWETH WETH = IWETH(wethAddress);
        WETH.deposit{value: msg.value}();
        WETH.transfer(msg.sender, msg.value);

        SupplyLogic.deposit(
            DataTypes.DepositParams({reserve: reserve, amount: msg.value})
        );

        emit Deposit(msg.sender, reserve, msg.value);
    }

    /// @notice Withdraw an asset from the reserve
    /// @param reserve The reserve to be withdrawn from
    /// @param amount Amount of the asset to be withdrawn
    function withdraw(address reserve, uint256 amount)
        external
        override
        nonReentrant
    {
        require(_validReserves[reserve] == true, "Invalid Reserve");

        SupplyLogic.withdraw(
            _addressProvider,
            DataTypes.WithdrawalParams({
                reserve: reserve,
                depositor: msg.sender,
                amount: amount
            })
        );

        emit Withdraw(msg.sender, reserve, amount);
    }

    /// @notice Withdraw an asset from the reserve
    /// @param amount Amount of the asset to be withdrawn
    function withdrawETH(address reserve, uint256 amount)
        external
        override
        nonReentrant
    {
        address wethAddress = _addressProvider.getWETH();

        require(_validReserves[reserve] == true, "Invalid Reserve");
        require(
            IReserve(reserve).getAsset() == wethAddress,
            "Reserve underlying is not WETH"
        );

        SupplyLogic.withdraw(
            _addressProvider,
            DataTypes.WithdrawalParams({
                reserve: reserve,
                depositor: address(this),
                amount: amount
            })
        );
        IWETH(wethAddress).withdraw(amount);

        (bool sent, ) = msg.sender.call{value: amount}("");
        require(sent, "Failed to send Ether");

        emit Withdraw(msg.sender, reserve, amount);
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
            DataTypes.BorrowParams({
                depositor: address(this),
                asset: wethAddress,
                amount: amount,
                nftAddress: nftAddress,
                nftTokenID: nftTokenId,
                genesisNFTId: genesisNFTId,
                request: request,
                packet: packet
            })
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
            DataTypes.BorrowParams({
                depositor: msg.sender,
                asset: asset,
                amount: amount,
                nftAddress: nftAddress,
                nftTokenID: nftTokenId,
                genesisNFTId: genesisNFTId,
                request: request,
                packet: packet
            })
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

        BorrowLogic.repay(
            _addressProvider,
            DataTypes.RepayParams({loanId: loanId, amount: msg.value})
        );

        emit Repay(msg.sender, loanId);
    }

    /// @notice Repay an an active loan
    /// @param loanId The ID of the loan to be paid
    function repay(uint256 loanId, uint256 amount)
        external
        override
        nonReentrant
    {
        BorrowLogic.repay(
            _addressProvider,
            DataTypes.RepayParams({loanId: loanId, amount: amount})
        );

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
        LiquidationLogic.liquidate(
            _addressProvider,
            DataTypes.LiquidationParams({
                loanId: loanId,
                request: request,
                packet: packet
            })
        );

        emit Liquidate(msg.sender, loanId);
    }

    function _setReserve(
        address collection,
        address asset,
        address reserve
    ) internal {
        _reserves[collection][asset] = reserve;

        emit SetReserve(collection, asset, reserve);
    }

    /// @notice Create a new reserve for a certain collection
    /// @param collection The collection using this reserve
    /// @param asset The address of the asset the reserve controls
    function createReserve(address collection, address asset) external {
        require(
            collection.supportsInterface(type(IERC721).interfaceId),
            "Collection address is not ERC721 compliant."
        );
        require(
            ITokenOracle(_addressProvider.getTokenOracle()).isTokenSupported(
                asset
            ),
            "Underlying Asset is not supported"
        );
        require(
            _reserves[collection][asset] == address(0),
            "Reserve already exists"
        );
        IReserve newReserve = new Reserve(
            _addressProvider,
            owner(),
            asset,
            string.concat(IERC20Metadata(asset).name(), " leNFT Reserve"),
            string.concat("R", IERC20Metadata(asset).symbol()),
            _defaultLiquidationPenalty,
            _defaultProtocolLiquidationFee,
            _defaultMaximumUtilizationRate,
            _defaultUnderlyingSafeguard
        );

        // Approve reserve use of Market balance
        IERC20(asset).approve(address(newReserve), 2**256 - 1);

        // Approve Market use of loan center NFT's (for returning the collateral)
        if (
            IERC721(collection).isApprovedForAll(
                _addressProvider.getLoanCenter(),
                address(this)
            ) == false
        ) {
            ILoanCenter(_addressProvider.getLoanCenter()).approveNFTCollection(
                collection
            );
        }

        _validReserves[address(newReserve)] = true;
        _setReserve(collection, asset, address(newReserve));

        emit CreateReserve(address(newReserve));
    }

    /// @notice Get the reserve address responsible to a certain asset
    /// @param asset The asset the reserve is responsible for
    /// @return The address of the reserve responsible for the asset
    function getReserve(address collection, address asset)
        external
        view
        override
        returns (address)
    {
        return _reserves[collection][asset];
    }

    function setReserve(
        address collection,
        address asset,
        address reserve
    ) external onlyOwner {
        _setReserve(collection, asset, reserve);
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

    function getDefaultLiquidationPenalty() external view returns (uint256) {
        return _defaultLiquidationPenalty;
    }

    function getDefaultProtocolLiquidationFee()
        external
        view
        returns (uint256)
    {
        return _defaultProtocolLiquidationFee;
    }

    function getDefaultMaximumUtilizationRate()
        external
        view
        returns (uint256)
    {
        return _defaultMaximumUtilizationRate;
    }

    function getDefaultUnderlyingSafeguard() external view returns (uint256) {
        return _defaultUnderlyingSafeguard;
    }

    // Add receive ETH function
    receive() external payable {}
}
