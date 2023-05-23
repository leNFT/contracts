// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.8.19;

import {ILendingMarket} from "../../interfaces/ILendingMarket.sol";
import {IInterestRate} from "../../interfaces/IInterestRate.sol";
import {ITokenOracle} from "../../interfaces/ITokenOracle.sol";
import {LiquidationLogic} from "../../libraries/logic/LiquidationLogic.sol";
import {BorrowLogic} from "../../libraries/logic/BorrowLogic.sol";
import {DataTypes} from "../../libraries/types/DataTypes.sol";
import {ConfigTypes} from "../../libraries/types/ConfigTypes.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {IAddressesProvider} from "../../interfaces/IAddressesProvider.sol";
import {ILoanCenter} from "../../interfaces/ILoanCenter.sol";
import {ILendingPool} from "../../interfaces/ILendingPool.sol";
import {IERC20MetadataUpgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/IERC20MetadataUpgradeable.sol";
import {IERC721Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC721/IERC721Upgradeable.sol";
import {IERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import {ERC721Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC721/ERC721Upgradeable.sol";
import {ERC165CheckerUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/introspection/ERC165CheckerUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import {Trustus} from "../Trustus/Trustus.sol";
import {LendingPool} from "./LendingPool.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";

/// @title LendingMarket Contract
/// @author leNFT
/// @notice This contract is the entrypoint for the leNFT lending protocol
/// @dev Call these contract functions to interact with the lending part of the protocol
contract LendingMarket is
    ILendingMarket,
    OwnableUpgradeable,
    ReentrancyGuardUpgradeable
{
    using ERC165CheckerUpgradeable for address;

    // collection + asset = pool
    mapping(address => mapping(address => address)) private _pools;

    // Number of pools per asset
    mapping(address => uint256) private _poolsCount;

    // The TVL safeguard for the lending pools
    uint256 private _tvlSafeguard;

    IAddressesProvider private _addressProvider;
    ConfigTypes.LendingPoolConfig private _defaultLendingPoolConfig;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// @notice Initialize the LendingMarket contract
    /// @param addressesProvider Address of the addresses provider contract
    /// @param tvlSafeguard The TVL safeguard for the lending pools
    /// @param defaultLendingPoolConfig The default lending pool configuration
    function initialize(
        IAddressesProvider addressesProvider,
        uint256 tvlSafeguard,
        ConfigTypes.LendingPoolConfig calldata defaultLendingPoolConfig
    ) external initializer {
        __Ownable_init();
        __ReentrancyGuard_init();
        _addressProvider = addressesProvider;
        _tvlSafeguard = tvlSafeguard;
        _defaultLendingPoolConfig = defaultLendingPoolConfig;
    }

    /// @notice Borrow an asset from a lending pool using an NFT as collateral
    /// @dev NFT approval needs to be given to the LoanCenter contract
    /// @param onBehalfOf The address of the user who will receive the borrowed tokens
    /// @param asset The address of the asset to be borrowed
    /// @param amount Amount of the asset to be borrowed
    /// @param nftAddress Address of the NFT collateral
    /// @param nftTokenIds Token id of the NFT collateral
    /// @param genesisNFTId Token id of the genesis NFT to be used for LTV boost
    /// @param request ID of the collateral price request sent by the trusted server
    /// @param packet Signed collateral price request sent by the trusted server
    function borrow(
        address onBehalfOf,
        address asset,
        uint256 amount,
        address nftAddress,
        uint256[] memory nftTokenIds,
        uint256 genesisNFTId,
        bytes32 request,
        Trustus.TrustusPacket calldata packet
    ) external override nonReentrant {
        BorrowLogic.borrow(
            _addressProvider,
            _pools[nftAddress][asset],
            DataTypes.BorrowParams({
                caller: msg.sender,
                onBehalfOf: onBehalfOf,
                asset: asset,
                amount: amount,
                nftAddress: nftAddress,
                nftTokenIds: nftTokenIds,
                genesisNFTId: genesisNFTId,
                request: request,
                packet: packet
            })
        );

        emit Borrow(msg.sender, asset, nftAddress, nftTokenIds, amount);
    }

    /// @notice Repay an an active loan
    /// @param loanId The ID of the loan to be paid
    /// @param amount Amount to be repaid
    function repay(
        uint256 loanId,
        uint256 amount
    ) external override nonReentrant {
        BorrowLogic.repay(
            _addressProvider,
            DataTypes.RepayParams({
                caller: msg.sender,
                loanId: loanId,
                amount: amount
            })
        );

        emit Repay(msg.sender, loanId);
    }

    /// @notice Liquidate an active loan
    /// @dev Needs to approve WETH transfers from Market address
    /// @param loanId The ID of the loan to be paid
    /// @param bid The amount to bid on the collateral
    /// @param request ID of the collateral price request sent by the trusted server
    /// @param packet Signed collateral price request sent by the trusted server
    function createLiquidationAuction(
        uint256 loanId,
        uint256 bid,
        bytes32 request,
        Trustus.TrustusPacket calldata packet
    ) external override nonReentrant {
        LiquidationLogic.createLiquidationAuction(
            _addressProvider,
            DataTypes.CreateAuctionParams({
                caller: msg.sender,
                loanId: loanId,
                bid: bid,
                request: request,
                packet: packet
            })
        );

        emit CreateLiquidationAuction(msg.sender, loanId, bid);
    }

    /// @notice Bid on a liquidation auction
    /// @dev Needs to approve WETH transfers from Market address
    /// @param loanId The ID of the loan to be paid
    /// @param bid The bid amount
    function bidLiquidationAuction(
        uint256 loanId,
        uint256 bid
    ) external override nonReentrant {
        LiquidationLogic.bidLiquidationAuction(
            _addressProvider,
            DataTypes.AuctionBidParams({
                caller: msg.sender,
                loanId: loanId,
                bid: bid
            })
        );

        emit BidLiquidationAuction(msg.sender, loanId, bid);
    }

    /// @notice Claim the collateral of a liquidated loan
    /// @param loanId The ID of the loan to be claimmed
    function claimLiquidation(uint256 loanId) external override nonReentrant {
        LiquidationLogic.claimLiquidation(
            _addressProvider,
            DataTypes.ClaimLiquidationParams({loanId: loanId})
        );
        emit ClaimLiquidation(msg.sender, loanId);
    }

    /// @notice Set the lending pool address for a certain collection and asset
    /// @param collection The collection using this lending vault
    /// @param asset The address of the asset the lending vault controls
    /// @param lendingPool The address of the lending pool
    function _setLendingPool(
        address collection,
        address asset,
        address lendingPool
    ) internal {
        _pools[collection][asset] = lendingPool;

        emit SetLendingPool(collection, asset, lendingPool);
    }

    /// @notice Create a new lending vault for a certain collection
    /// @param collection The collection using this lending pool
    /// @param asset The address of the asset the lending pool controls
    function createLendingPool(
        address collection,
        address asset
    ) external returns (address) {
        require(
            collection.supportsInterface(type(IERC721Upgradeable).interfaceId),
            "LM:CLP:COLLECTION_NOT_NFT"
        );
        require(
            ITokenOracle(_addressProvider.getTokenOracle()).isTokenSupported(
                asset
            ),
            "LM:CLP:ASSET_NOT_SUPPORTED_TO"
        );
        require(
            IInterestRate(_addressProvider.getInterestRate()).isTokenSupported(
                asset
            ),
            "LM:CLP:ASSET_NOT_SUPPORTED_IR"
        );
        require(
            _pools[collection][asset] == address(0),
            "LM:CLP:LENDING_POOL_EXISTS"
        );
        ILendingPool newLendingPool = new LendingPool(
            _addressProvider,
            owner(),
            asset,
            string.concat(
                "leNFT ",
                IERC20MetadataUpgradeable(asset).symbol(),
                " Lending #",
                Strings.toString(_poolsCount[asset])
            ),
            string.concat(
                "leL",
                IERC20MetadataUpgradeable(asset).symbol(),
                "-",
                Strings.toString(_poolsCount[asset])
            ),
            _defaultLendingPoolConfig
        );

        // Approve lending pool use of market balance
        IERC20Upgradeable(asset).approve(address(newLendingPool), 2 ** 256 - 1);

        // Approve Market use of loan center NFT's (for returning the collateral)
        if (
            IERC721Upgradeable(collection).isApprovedForAll(
                _addressProvider.getLoanCenter(),
                address(this)
            ) == false
        ) {
            ILoanCenter(_addressProvider.getLoanCenter()).approveNFTCollection(
                collection
            );
        }

        _setLendingPool(collection, asset, address(newLendingPool));
        _poolsCount[asset] += 1;

        emit CreateLendingPool(address(newLendingPool));

        return address(newLendingPool);
    }

    /// @notice Get the Lending Pool address responsible to a certain asset
    /// @param collection The collection supported by the Lending Pool
    /// @param asset The asset supported by the Lending Pool
    /// @return The address of the Lending Pool
    function getLendingPool(
        address collection,
        address asset
    ) external view override returns (address) {
        return _pools[collection][asset];
    }

    /// @notice Sets the lending pool addresses for a given collection, asset, and lending pool
    /// @dev To be used when migrating an asset's lending pool
    /// @param collection The collection address
    /// @param asset The asset address
    /// @param pool The lending pool address
    function setLendingPool(
        address collection,
        address asset,
        address pool
    ) external onlyOwner {
        _setLendingPool(collection, asset, pool);
    }

    /// @notice Sets the default pool configuration
    /// @param poolConfig The new pool configuration
    function setDefaultPoolConfig(
        ConfigTypes.LendingPoolConfig memory poolConfig
    ) external onlyOwner {
        _defaultLendingPoolConfig = poolConfig;
    }

    /// @notice Returns the default pool configuration
    /// @return The default pool configuration
    function getDefaultPoolConfig()
        external
        view
        returns (ConfigTypes.LendingPoolConfig memory)
    {
        return _defaultLendingPoolConfig;
    }

    /// @notice Sets the TVL safeguard value
    /// @param tvlSafeguard The new TVL safeguard value
    function setTVLSafeguard(uint256 tvlSafeguard) external onlyOwner {
        _tvlSafeguard = tvlSafeguard;
    }

    /// @notice Returns the current TVL safeguard value
    /// @return The current TVL safeguard value
    function getTVLSafeguard() external view returns (uint256) {
        return _tvlSafeguard;
    }
}
