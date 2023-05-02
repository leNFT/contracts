// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.8.19;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {ERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {IAddressesProvider} from "../interfaces/IAddressesProvider.sol";
import {INativeToken} from "../interfaces/INativeToken.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import {IGaugeController} from "../interfaces/IGaugeController.sol";
import {ContextUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ContextUpgradeable.sol";
import {DataTypes} from "../libraries/types/DataTypes.sol";

/// @title NativeToken
/// @notice Provides functionality for minting, burning, and distributing native tokens
contract NativeToken is
    Initializable,
    ContextUpgradeable,
    INativeToken,
    ERC20Upgradeable,
    OwnableUpgradeable,
    ReentrancyGuardUpgradeable
{
    IAddressesProvider private _addressProvider;
    uint256 private _deployTimestamp;
    uint256 private _cap;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// @notice Initializes the contract with the specified parameters
    /// @param addressProvider The address provider contract
    /// @param name The name of the token
    /// @param symbol The symbol of the token
    /// @param cap The maximum supply of the token
    function initialize(
        IAddressesProvider addressProvider,
        string calldata name,
        string calldata symbol,
        uint256 cap
    ) external initializer {
        __Ownable_init();
        __ERC20_init(name, symbol);
        _addressProvider = addressProvider;
        _cap = cap;
        _deployTimestamp = block.timestamp;
    }

    /// @notice Gets the maximum supply of the token
    /// @return The maximum supply of the token
    function getCap() public view returns (uint256) {
        return _cap;
    }

    /// @notice Mints tokens and assigns them to the specified account
    /// @param account The account to receive the tokens
    /// @param amount The amount of tokens to mint
    function mint(address account, uint256 amount) external onlyOwner {
        _mint(account, amount);
    }

    /// @notice Internal function to mint tokens and assign them to the specified account
    /// @param account The account to receive the tokens
    /// @param amount The amount of tokens to mint
    function _mint(address account, uint256 amount) internal override {
        require(
            ERC20Upgradeable.totalSupply() + amount <= getCap(),
            "NativeToken: cap exceeded"
        );
        ERC20Upgradeable._mint(account, amount);
    }

    /// @notice Mints genesis tokens and assigns them to the Genesis NFT contract
    /// @dev The caller must be the Genesis NFT contract.
    /// @param amount The amount of tokens to mint
    function mintGenesisTokens(uint256 amount) external {
        require(
            _msgSender() == _addressProvider.getGenesisNFT(),
            "Genesis tokens can only be minted by the Genesis NFT contract"
        );
        _mint(_addressProvider.getGenesisNFT(), amount);
    }

    /// @notice Burns the specified amount of tokens for the Genesis contract.
    /// @dev The caller must be the Genesis NFT contract.
    ///@param amount The amount of Genesis tokens to burn.
    function burnGenesisTokens(uint256 amount) external {
        require(
            _msgSender() == _addressProvider.getGenesisNFT(),
            "Genesis tokens can only be burned by the Genesis NFT contract"
        );
        _burn(_addressProvider.getGenesisNFT(), amount);
    }

    /// @notice Mints the specified amount of gauge rewards to the specified receiver.
    /// @dev The caller must be an approved gauge.
    /// @param receiver The address to receive the gauge rewards.
    /// @param amount The amount of gauge rewards to mint.
    function mintGaugeRewards(
        address receiver,
        uint256 amount
    ) external override {
        require(
            IGaugeController(_addressProvider.getGaugeController()).isGauge(
                _msgSender()
            ),
            "Gauge rewards can only be minted by an approved gauge"
        );
        _mint(receiver, amount);
    }

    function mintRebates(address receiver, uint256 amount) external override {
        require(
            _msgSender() == _addressProvider.getVotingEscrow(),
            "Rebates can only be minted by the Voting Escrow contract"
        );
        _mint(receiver, amount);
    }
}
