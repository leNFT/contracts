// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.8.17;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {ERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {IAddressesProvider} from "../interfaces/IAddressesProvider.sol";
import {INativeToken} from "../interfaces/INativeToken.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "hardhat/console.sol";
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
    uint256 public constant INFLATION_PERIOD = 52; // 52 epochs (1 year)
    uint256 public constant LOADING_PERIOD = 24; // 24 epochs (6 months)

    IAddressesProvider private _addressProvider;
    address private _devAddress;
    uint256 private _deployTimestamp;
    uint256 private _devReward;
    uint256 private _devVestingTime;
    uint256 private _devWithdrawn;
    uint256 private _cap;
    uint256 private _initialRewards;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// @notice Initializes the contract with the specified parameters
    /// @param addressProvider The address provider contract
    /// @param name The name of the token
    /// @param symbol The symbol of the token
    /// @param cap The maximum supply of the token
    /// @param devAddress The address of the developer
    /// @param devReward The amount of tokens allocated to the developer
    /// @param devVestingTime The duration of the developer's vesting period in seconds
    /// @param initialRewards The initial rewards rate for the token
    function initialize(
        IAddressesProvider addressProvider,
        string calldata name,
        string calldata symbol,
        uint256 cap,
        address devAddress,
        uint256 devReward,
        uint256 devVestingTime,
        uint256 initialRewards
    ) external initializer {
        __Ownable_init();
        __ERC20_init(name, symbol);
        _addressProvider = addressProvider;
        _cap = cap;
        _deployTimestamp = block.timestamp;
        _devAddress = devAddress;
        _devReward = devReward;
        _devVestingTime = devVestingTime;
        _initialRewards = initialRewards;
    }

    /// @notice Gets the maximum supply of the token
    /// @return The maximum supply of the token
    function getCap() public view returns (uint256) {
        return _cap;
    }

    /// @notice Mints tokens and assigns them to the specified account
    /// @param account The account to receive the tokens
    /// @param amount The amount of tokens to mint
    function mint(address account, uint256 amount) external {
        _mintTokens(account, amount);
    }

    /// @notice Internal function to mint tokens and assign them to the specified account
    /// @param account The account to receive the tokens
    /// @param amount The amount of tokens to mint
    function _mintTokens(address account, uint256 amount) internal {
        require(
            ERC20Upgradeable.totalSupply() + amount <= getCap(),
            "NativeToken: cap exceeded"
        );
        _mint(account, amount);
    }

    /// @notice Mints genesis tokens and assigns them to the Genesis NFT contract
    /// @dev The caller must be the Genesis NFT contract.
    /// @param amount The amount of tokens to mint
    function mintGenesisTokens(uint256 amount) external {
        require(
            _msgSender() == _addressProvider.getGenesisNFT(),
            "Genesis tokens can only be minted by the Genesis NFT contract"
        );
        _mintTokens(_addressProvider.getGenesisNFT(), amount);
    }

    /// @notice Burns the specified amount of Genesis tokens.
    /// @dev The caller must be the Genesis NFT contract.
    ///@param amount The amount of Genesis tokens to burn.
    function burnGenesisTokens(uint256 amount) external {
        require(
            _msgSender() == _addressProvider.getGenesisNFT(),
            "Genesis tokens can only be burned by the Genesis NFT contract"
        );
        _burn(_addressProvider.getGenesisNFT(), amount);
    }

    /// @notice Returns the amount of tokens to distribute as rewards for the specified epoch.
    /// @param epoch The epoch for which to get the rewards.
    /// @return The amount of tokens to distribute as rewards for the specified epoch.
    function getEpochRewards(
        uint256 epoch
    ) external view override returns (uint256) {
        // If we are in the loading period, return smaller rewards
        if (epoch < LOADING_PERIOD) {
            return (_initialRewards * epoch) / LOADING_PERIOD;
        }

        uint256 inflationEpoch = epoch / INFLATION_PERIOD;

        return
            (_initialRewards * (3 ** inflationEpoch)) / (4 ** inflationEpoch);
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
        _mintTokens(receiver, amount);
    }

    /// @notice Returns the amount of unvested developer reward tokens.
    /// @return The amount of unvested developer reward tokens.
    function getDevRewardTokens() public view returns (uint256) {
        uint256 unvestedTokens;
        if (block.timestamp - _deployTimestamp < _devVestingTime) {
            unvestedTokens = ((_devReward *
                (block.timestamp - _deployTimestamp)) / _devVestingTime);
        } else {
            unvestedTokens = _devReward;
        }

        return unvestedTokens - _devWithdrawn;
    }

    /// @notice Mints the specified amount of developer reward tokens to the developer address.
    /// @dev The caller must be the developer.
    /// @dev The amount must be less than or equal to the unvested developer reward tokens.
    /// @param amount The amount of developer reward tokens to mint.
    function mintDevRewardTokens(uint256 amount) external {
        // Require that the caller is the developer
        require(_msgSender() == _devAddress, "Caller must be dev");

        //Should only be able to withdrawn unvested tokens
        require(
            getDevRewardTokens() >= amount,
            "Amount bigger than allowed by vesting"
        );
        _mintTokens(_devAddress, amount);
        _devWithdrawn += amount;
    }
}
