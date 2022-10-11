// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.8.15;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {ERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {IAddressesProvider} from "../interfaces/IAddressesProvider.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "hardhat/console.sol";

contract NativeToken is
    Initializable,
    ERC20Upgradeable,
    OwnableUpgradeable,
    ReentrancyGuardUpgradeable
{
    IAddressesProvider private _addressProvider;
    address private _devAddress;
    uint256 internal _deployTimestamp;
    uint256 internal _devReward;
    uint256 internal _devVestingTime;
    uint256 internal _devWithdrawn;
    uint256 internal _cap;
    uint256 internal _lastRewardsTimestamp;
    uint256 internal _rewardsFactor;
    uint256 internal _rewardsPeriod;
    uint256 internal _maxPeriods;

    event DistributeRewards(uint256 _amount);

    function initialize(
        IAddressesProvider addressProvider,
        string calldata name,
        string calldata symbol,
        uint256 cap,
        address devAddress,
        uint256 devReward,
        uint256 devVestingTime,
        uint256 rewardsPeriod,
        uint256 maxPeriods,
        uint256 rewardsFactor
    ) external initializer {
        __Ownable_init();
        __ERC20_init(name, symbol);
        _addressProvider = addressProvider;
        _cap = cap;
        _deployTimestamp = block.timestamp;
        _devAddress = devAddress;
        _devReward = devReward;
        _devVestingTime = devVestingTime;
        _rewardsPeriod = rewardsPeriod;
        _maxPeriods = maxPeriods;
        _rewardsFactor = rewardsFactor;
    }

    function getCap() public view returns (uint256) {
        return _cap;
    }

    function mint(address account, uint256 amount) external onlyOwner {
        _mintTokens(account, amount);
    }

    function _mintTokens(address account, uint256 amount) internal {
        require(
            ERC20Upgradeable.totalSupply() + amount <= getCap(),
            "NativeToken: cap exceeded"
        );
        _mint(account, amount);
    }

    function getRewardsFactor() external view returns (uint256) {
        return _rewardsFactor;
    }

    function setRewardsFactor(uint256 rewardsFactor) external onlyOwner {
        _rewardsFactor = rewardsFactor;
    }

    function getMaxPeriods() external view returns (uint256) {
        return _maxPeriods;
    }

    function setMaxPeriods(uint256 maxPeriods) external onlyOwner {
        _maxPeriods = maxPeriods;
    }

    function getRewardsPeriod() external view returns (uint256) {
        return _rewardsPeriod;
    }

    function setRewardsPeriod(uint256 rewardsPeriod) external onlyOwner {
        _rewardsPeriod = rewardsPeriod;
    }

    function mintGenesisTokens(address receiver, uint256 amount) external {
        require(msg.sender == _addressProvider.getGenesisNFT());
        _mintTokens(receiver, amount);
    }

    function getRewards() public view returns (uint256) {
        uint256 rewards = 0;

        if (_maxPeriods * _rewardsPeriod > block.timestamp - _deployTimestamp) {
            rewards =
                (_rewardsFactor *
                    (_maxPeriods *
                        _rewardsPeriod +
                        _deployTimestamp -
                        block.timestamp)) /
                (_maxPeriods * _rewardsPeriod);
        }

        return rewards;
    }

    function distributeRewards() external nonReentrant {
        //The rewards can only be distributed if the rewards period has passed
        require(
            _lastRewardsTimestamp + _rewardsPeriod < block.timestamp,
            "Not enough time since last rewards distribution."
        );

        // Only give rewards until the max periods are over
        require(
            _maxPeriods * _rewardsPeriod > block.timestamp - _deployTimestamp,
            "Rewards period is over"
        );

        uint256 amount = getRewards();
        _mintTokens(_addressProvider.getNativeTokenVault(), amount);

        // Update last rewards variable
        _lastRewardsTimestamp = block.timestamp;

        emit DistributeRewards(amount);
    }

    function getDevRewards() public view returns (uint256) {
        uint256 unvestedTokens;
        if (block.timestamp - _deployTimestamp < _devVestingTime) {
            unvestedTokens = ((_devReward *
                (block.timestamp - _deployTimestamp)) / _devVestingTime);
        } else {
            unvestedTokens = _devReward;
        }

        return unvestedTokens - _devWithdrawn;
    }

    function mintDevRewards(uint256 amount) external {
        // Require that the caller is the developer
        require(_msgSender() == _devAddress, "Caller must be dev");

        //Should only be able to withdrawn unvested tokens
        require(
            getDevRewards() >= amount,
            "Amount bigger than allowed by vesting"
        );
        _mintTokens(_devAddress, amount);
        _devWithdrawn += amount;
    }
}
