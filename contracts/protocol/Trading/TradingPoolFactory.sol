// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.8.17;

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

    uint256 private _defaultSwapFee;

    using ERC165Checker for address;

    // Initialize the market
    function initialize(
        IAddressesProvider addressesProvider,
        uint256 defaultSwapFee
    ) external initializer {
        __Ownable_init();
        _addressProvider = addressesProvider;
        _defaultSwapFee = defaultSwapFee;
    }

    function setDefaultSwapFee(uint256 newSwapFee) external {
        _defaultSwapFee = newSwapFee;
    }

    function getDefaultSwapFee() external view returns (uint256) {
        return _defaultSwapFee;
    }

    function getTradingPool(
        address nft,
        address token
    ) external view returns (address) {
        return _pools[nft][token];
    }

    /// @notice Create a trading pool for a certain collection
    /// @param nft The nft collection
    /// @param token The token to trade against
    function createTradingPool(address nft, address token) external {
        require(
            nft.supportsInterface(type(IERC721).interfaceId),
            "Collection address is not ERC721 compliant."
        );
        require(
            _pools[nft][token] == address(0),
            "Trading Pool already exists"
        );
        ITradingPool newTradingPool = new TradingPool(
            _addressProvider,
            owner(),
            IERC20(token),
            nft,
            _defaultSwapFee,
            string.concat(
                "leNFT Trading Pool ",
                IERC20Metadata(token).symbol(),
                " - ",
                IERC721Metadata(nft).symbol()
            ),
            string.concat(
                "leT",
                IERC20Metadata(token).symbol(),
                "-",
                IERC721Metadata(nft).symbol()
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
