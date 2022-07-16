// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.8.15;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {ERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {IMarketAddressesProvider} from "../interfaces/IMarketAddressesProvider.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

contract NativeToken is Initializable, ERC20Upgradeable, OwnableUpgradeable {
    IMarketAddressesProvider private _addressProvider;
    uint256 internal _cap;

    function initialize(
        IMarketAddressesProvider addressProvider,
        string calldata name,
        string calldata symbol,
        uint256 cap
    ) external initializer {
        __Ownable_init();
        __ERC20_init(name, symbol);
        _addressProvider = addressProvider;
        _cap = cap;
    }

    function getCap() public view virtual returns (uint256) {
        return _cap;
    }

    function distributeRewards(uint256 amount) external onlyOwner {
        address nativeTokenVaultAddress = _addressProvider
            .getNativeTokenVault();
        _mint(nativeTokenVaultAddress, amount);
    }

    function mint(address account, uint256 amount) external onlyOwner {
        require(
            ERC20Upgradeable.totalSupply() + amount <= getCap(),
            "NativeToken: cap exceeded"
        );
        _mint(account, amount);
    }

    // TODO: DELETE THIS BEFORE MAINNET
    function testMint(address account, uint256 amount) external {
        require(
            ERC20Upgradeable.totalSupply() + amount <= getCap(),
            "NativeToken: cap exceeded"
        );
        _mint(account, amount);
    }
}
