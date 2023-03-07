// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.8.19;

import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {IAddressesProvider} from "../../interfaces/IAddressesProvider.sol";
import {ITradingPool} from "../../interfaces/ITradingPool.sol";
import {ITradingPoolFactory} from "../../interfaces/ITradingPoolFactory.sol";
import {ContextUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ContextUpgradeable.sol";
import {TradingPool} from "./TradingPool.sol";
import {ISwapRouter} from "../../interfaces/ISwapRouter.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IERC721Metadata} from "@openzeppelin/contracts/token/ERC721/extensions/IERC721Metadata.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {ERC165Checker} from "@openzeppelin/contracts/utils/introspection/ERC165Checker.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";

/// @title TradingPoolFactory Contract
/// @author leNFT
/// @notice This contract is responsible for creating new trading pools
contract TradingPoolFactory is
    Initializable,
    ITradingPoolFactory,
    ContextUpgradeable,
    OwnableUpgradeable,
    ReentrancyGuardUpgradeable
{
    IAddressesProvider private _addressProvider;

    // collection + asset = pool
    mapping(address => mapping(address => address)) private _pools;

    uint256 private _protocolFee;
    uint256 private _tvlSafeguard;

    using ERC165Checker for address;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// @notice Initialize the contract
    /// @param addressesProvider Address of the AddressesProvider contract
    /// @param protocolFee Protocol fee percentage charged on trades
    /// @param tvlSafeguard default TVL safeguard for pools
    function initialize(
        IAddressesProvider addressesProvider,
        uint256 protocolFee,
        uint256 tvlSafeguard
    ) external initializer {
        __Ownable_init();
        _addressProvider = addressesProvider;
        _protocolFee = protocolFee;
        _tvlSafeguard = tvlSafeguard;
    }

    /// @notice Set the protocol fee percentage
    /// @param newProtocolFee New protocol fee percentage
    function setProtocolFee(uint256 newProtocolFee) external onlyOwner {
        _protocolFee = newProtocolFee;
    }

    /// @notice Get the current protocol fee percentage
    /// @return Current protocol fee percentage
    function getProtocolFee() external view returns (uint256) {
        return _protocolFee;
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
    /// @param token The token address to trade against
    /// @return The address of the trading pool for the given NFT collection and token
    function getTradingPool(
        address nft,
        address token
    ) external view returns (address) {
        return _pools[nft][token];
    }

    /// @notice Creates a trading pool for a certain collection and token
    /// @param nft The NFT collection address
    /// @param token The token address to trade against
    function createTradingPool(
        address nft,
        address token
    ) external nonReentrant {
        require(
            nft.supportsInterface(type(IERC721).interfaceId),
            "Collection address is not ERC721 compliant."
        );
        require(
            _pools[nft][token] == address(0),
            "Trading Pool for pair already exists"
        );
        ITradingPool newTradingPool = new TradingPool(
            _addressProvider,
            owner(),
            token,
            nft,
            string.concat(
                "leNFT Trading Pool ",
                IERC721Metadata(nft).symbol(),
                " - ",
                IERC20Metadata(token).symbol()
            ),
            string.concat(
                "leT",
                IERC721Metadata(nft).symbol(),
                "-",
                IERC20Metadata(token).symbol()
            )
        );

        _pools[nft][token] = address(newTradingPool);

        // Approve trading pool in swap router
        ISwapRouter(_addressProvider.getSwapRouter()).approveTradingPool(
            token,
            address(newTradingPool)
        );

        emit CreateTradingPool(address(newTradingPool), nft, token);
    }
}
