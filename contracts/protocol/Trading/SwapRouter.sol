// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.8.17;

import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {IAddressesProvider} from "../../interfaces/IAddressesProvider.sol";
import {ITradingPool} from "../../interfaces/ITradingPool.sol";
import {ITradingPoolFactory} from "../../interfaces/ITradingPoolFactory.sol";
import {ContextUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ContextUpgradeable.sol";
import {TradingPool} from "./TradingPool.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IERC721Metadata} from "@openzeppelin/contracts/token/ERC721/extensions/IERC721Metadata.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {ERC165Checker} from "@openzeppelin/contracts/utils/introspection/ERC165Checker.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";

/// @title SwapRouter Contract
/// @author leNFT
/// @notice This contract is responsible for swapping between assets in different pools
contract SwapRouter is Initializable, OwnableUpgradeable {
    IAddressesProvider private _addressProvider;

    using SafeERC20 for IERC20;

    // Initialize the market
    function initialize(
        IAddressesProvider addressesProvider
    ) external initializer {
        __Ownable_init();
        _addressProvider = addressesProvider;
    }

    function swap(
        ITradingPool buyPool,
        uint256[] memory buyNftIds,
        uint256 maximumBuyPrice,
        uint256 buyAmount,
        ITradingPool sellPool,
        uint256[] memory sellNftIds,
        uint256[] memory liquidityPairs,
        uint256 minimumSellPrice
    ) external {
        // Pools need to have the same underlying token
        require(
            buyPool.getToken() == sellPool.getToken(),
            "Underlying token mismatch."
        );

        uint256 sellPrice = sellPool.sell(
            msg.sender,
            sellNftIds,
            liquidityPairs,
            minimumSellPrice
        );

        if (buyAmount > 0) {
            IERC20(sellPool.getToken()).safeTransferFrom(
                msg.sender,
                address(this),
                buyAmount
            );
        }

        uint256 buyPrice = sellPool.buy(msg.sender, buyNftIds, maximumBuyPrice);

        //Send change back to user
        if (buyPrice > sellPrice + buyAmount) {
            IERC20(sellPool.getToken()).safeTransfer(
                msg.sender,
                sellPrice + buyAmount - buyPrice
            );
        }
    }
}
