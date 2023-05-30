// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.8.19;

import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {IAddressProvider} from "../../interfaces/IAddressProvider.sol";
import {ITradingPool} from "../../interfaces/ITradingPool.sol";
import {ITradingPoolFactory} from "../../interfaces/ITradingPoolFactory.sol";
import {TradingPool} from "./TradingPool.sol";
import {ISwapRouter} from "../../interfaces/ISwapRouter.sol";
import {IPricingCurve} from "../../interfaces/IPricingCurve.sol";
import {IERC20MetadataUpgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/IERC20MetadataUpgradeable.sol";
import {IERC721MetadataUpgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC721/extensions/IERC721MetadataUpgradeable.sol";
import {ERC721Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC721/ERC721Upgradeable.sol";
import {ERC165CheckerUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/introspection/ERC165CheckerUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";

/// @title TradingPoolFactory Contract
/// @author leNFT
/// @notice This contract is responsible for creating new trading pools
contract TradingPoolFactory is
    ITradingPoolFactory,
    OwnableUpgradeable,
    ReentrancyGuardUpgradeable
{
    IAddressProvider private _addressProvider;

    // collection + asset = pool
    mapping(address => mapping(address => address)) private _pools;

    // mapping of valid pools
    mapping(address => bool) private _isTradingPool;

    // mapping of valid price curves
    mapping(address => bool) private _isPriceCurve;

    uint256 private _protocolFeePercentage;
    uint256 private _tvlSafeguard;

    using ERC165CheckerUpgradeable for address;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// @notice Initialize the contract
    /// @param addressProvider Address of the addressProvider contract
    /// @param protocolFeePercentage Protocol fee percentage charged on lp trade fees
    /// @param tvlSafeguard default TVL safeguard for pools
    function initialize(
        IAddressProvider addressProvider,
        uint256 protocolFeePercentage,
        uint256 tvlSafeguard
    ) external initializer {
        __Ownable_init();
        __ReentrancyGuard_init();
        _addressProvider = addressProvider;
        _protocolFeePercentage = protocolFeePercentage;
        _tvlSafeguard = tvlSafeguard;
    }

    function isPriceCurve(
        address priceCurve
    ) external view override returns (bool) {
        return _isPriceCurve[priceCurve];
    }

    function setPriceCurve(address priceCurve, bool valid) external onlyOwner {
        // Make sure the price curve is valid
        require(
            priceCurve.supportsInterface(type(IPricingCurve).interfaceId),
            "TPF:SPC:NOT_PC"
        );
        _isPriceCurve[priceCurve] = valid;
    }

    /// @notice Set the protocol fee percentage
    /// @param newProtocolFeePercentage New protocol fee percentage
    function setProtocolFeePercentage(
        uint256 newProtocolFeePercentage
    ) external onlyOwner {
        _protocolFeePercentage = newProtocolFeePercentage;
    }

    /// @notice Get the current protocol fee percentage
    /// @return Current protocol fee percentage
    function getProtocolFeePercentage() external view returns (uint256) {
        return _protocolFeePercentage;
    }

    /// @notice Get the current TVL safeguard
    /// @return Current TVL safeguard
    function getTVLSafeguard() external view returns (uint256) {
        return _tvlSafeguard;
    }

    /// @notice Sets a new value for the TVL safeguard
    /// @param newTVLSafeguard The new TVL safeguard value to be set
    function setTVLSafeguard(uint256 newTVLSafeguard) external onlyOwner {
        _tvlSafeguard = newTVLSafeguard;
    }

    /// @notice Returns the address of the trading pool for a certain collection and token
    /// @param nft The NFT collection address
    /// @param token The token address
    /// @return The address of the trading pool for the given NFT collection and token
    function getTradingPool(
        address nft,
        address token
    ) external view returns (address) {
        return _pools[nft][token];
    }

    /// @notice Sets the address of the trading pool for a certain collection and token
    /// @dev Meant to be used by owner if there's a need to update or delete a pool
    /// @param nft The NFT collection address
    /// @param token The token address
    /// @param pool The address of the trading pool for the given NFT collection and token
    function setTradingPool(
        address nft,
        address token,
        address pool
    ) external onlyOwner {
        // Make sure the pool supports the interface or is the zero address
        require(
            pool.supportsInterface(type(ITradingPool).interfaceId) ||
                pool == address(0),
            "TPF:STP:NOT_POOL"
        );

        // If not zero address, make sure the pool is for the correct nft and token
        if (pool != address(0)) {
            require(
                ITradingPool(pool).getNFT() == nft &&
                    ITradingPool(pool).getToken() == token,
                "TPF:STP:INVALID_POOL"
            );
        }

        _setTradingPool(nft, token, pool);
    }

    function _setTradingPool(
        address nft,
        address token,
        address pool
    ) internal {
        _pools[nft][token] = pool;

        emit SetTradingPool(pool, nft, token);
    }

    /// @notice Returns whether a pool is valid or not
    /// @param pool The address of the pool to check
    /// @return Whether the pool is valid or not
    function isTradingPool(address pool) external view returns (bool) {
        return _isTradingPool[pool];
    }

    /// @notice Creates a trading pool for a certain collection and token
    /// @param nft The NFT collection address
    /// @param token The token address to trade against
    function createTradingPool(
        address nft,
        address token
    ) external nonReentrant {
        require(
            _pools[nft][token] == address(0),
            "TPF:CTP:POOL_ALREADY_EXISTS"
        );
        require(
            nft.supportsInterface(type(IERC721MetadataUpgradeable).interfaceId),
            "TPF:CTP:NFT_NOT_ERC721"
        );

        ITradingPool newTradingPool = new TradingPool(
            _addressProvider,
            owner(),
            token,
            nft,
            string.concat(
                "leNFT Trading Pool ",
                IERC721MetadataUpgradeable(nft).symbol(),
                " - ",
                IERC20MetadataUpgradeable(token).symbol()
            ),
            string.concat(
                "leT",
                IERC721MetadataUpgradeable(nft).symbol(),
                "-",
                IERC20MetadataUpgradeable(token).symbol()
            )
        );

        _setTradingPool(nft, token, address(newTradingPool));
        _isTradingPool[address(newTradingPool)] = true;

        // Approve trading pool in swap router
        ISwapRouter(_addressProvider.getSwapRouter()).approveTradingPool(
            token,
            address(newTradingPool)
        );

        emit CreateTradingPool(address(newTradingPool), nft, token);
    }
}
