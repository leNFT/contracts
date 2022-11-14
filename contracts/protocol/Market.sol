// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.8.17;

import {IMarket} from "../interfaces/IMarket.sol";
import {ITokenOracle} from "../interfaces/ITokenOracle.sol";
import {LiquidationLogic} from "../libraries/logic/LiquidationLogic.sol";
import {BorrowLogic} from "../libraries/logic/BorrowLogic.sol";
import {DataTypes} from "../libraries/types/DataTypes.sol";
import {ConfigTypes} from "../libraries/types/ConfigTypes.sol";
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
import {ContextUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ContextUpgradeable.sol";
import {Trustus} from "./Trustus/Trustus.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import "hardhat/console.sol";

/// @title Market Contract
/// @author leNFT
/// @notice This contract is the entrypoint for the leNFT protocol
/// @dev Call these contrcact functions to interact with the protocol
contract Market is
    Initializable,
    ContextUpgradeable,
    IMarket,
    OwnableUpgradeable,
    ReentrancyGuardUpgradeable
{
    using ERC165Checker for address;

    // collection + asset = reserve
    mapping(address => mapping(address => address)) private _reserves;

    // Number of reserves per asset
    mapping(address => uint256) private _reservesCount;

    IAddressesProvider private _addressProvider;
    ConfigTypes.ReserveConfig private _defaultReserveConfig;

    // Initialize the market
    function initialize(
        IAddressesProvider addressesProvider,
        ConfigTypes.ReserveConfig calldata defaultReserveConfig
    ) external initializer {
        __Ownable_init();
        _addressProvider = addressesProvider;
        _defaultReserveConfig = defaultReserveConfig;
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
        address onBehalfOf,
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
                caller: _msgSender(),
                onBehalfOf: onBehalfOf,
                asset: asset,
                amount: amount,
                nftAddress: nftAddress,
                nftTokenID: nftTokenId,
                genesisNFTId: genesisNFTId,
                request: request,
                packet: packet
            })
        );

        emit Borrow(_msgSender(), asset, nftAddress, nftTokenId, amount);
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
            DataTypes.RepayParams({
                caller: _msgSender(),
                loanId: loanId,
                amount: amount
            })
        );

        emit Repay(_msgSender(), loanId);
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
                caller: _msgSender(),
                loanId: loanId,
                request: request,
                packet: packet
            })
        );

        emit Liquidate(_msgSender(), loanId);
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
            IERC20(asset),
            string.concat(
                "leNFT ",
                IERC20Metadata(asset).symbol(),
                " Reserve #",
                Strings.toString(_reservesCount[asset])
            ),
            string.concat(
                "leR",
                IERC20Metadata(asset).symbol(),
                "-",
                Strings.toString(_reservesCount[asset])
            ),
            _defaultReserveConfig
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

        _setReserve(collection, asset, address(newReserve));
        _reservesCount[asset] += 1;

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

    function setCollectionReserve(
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
        _defaultReserveConfig.liquidationPenalty = liquidationPenalty;
    }

    function setDefaultProtocolLiquidationFee(uint256 protocolLiquidationFee)
        external
        onlyOwner
    {
        _defaultReserveConfig.protocolLiquidationFee = protocolLiquidationFee;
    }

    function setDefaultMaximumUtilizationRate(uint256 maximumUtilizationRate)
        external
        onlyOwner
    {
        _defaultReserveConfig.maximumUtilizationRate = maximumUtilizationRate;
    }

    function setDefaultTVLSafeguard(uint256 tvlSafeguard) external onlyOwner {
        _defaultReserveConfig.tvlSafeguard = tvlSafeguard;
    }

    function getDefaultLiquidationPenalty() external view returns (uint256) {
        return _defaultReserveConfig.liquidationPenalty;
    }

    function getDefaultProtocolLiquidationFee()
        external
        view
        returns (uint256)
    {
        return _defaultReserveConfig.protocolLiquidationFee;
    }

    function getDefaultMaximumUtilizationRate()
        external
        view
        returns (uint256)
    {
        return _defaultReserveConfig.maximumUtilizationRate;
    }

    function getDefaultTVLSafeguard() external view returns (uint256) {
        return _defaultReserveConfig.tvlSafeguard;
    }
}
