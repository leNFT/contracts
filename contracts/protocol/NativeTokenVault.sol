// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.8.15;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {ERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {IMarketAddressesProvider} from "../interfaces/IMarketAddressesProvider.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

contract NativeTokenVault is
    Initializable,
    ERC20Upgradeable,
    OwnableUpgradeable
{
    IMarketAddressesProvider internal _addressProvider;

    function initialize(
        IMarketAddressesProvider addressProvider,
        string calldata name,
        string calldata symbol
    ) external initializer {
        __Ownable_init();
        __ERC20_init(name, symbol);
        _addressProvider = addressProvider;
    }
}
