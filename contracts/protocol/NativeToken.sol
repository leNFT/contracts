// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.8.15;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {ERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {IAddressesProvider} from "../interfaces/IAddressesProvider.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

contract NativeToken is Initializable, ERC20Upgradeable, OwnableUpgradeable {
    IAddressesProvider private _addressProvider;
    address private _devAddress;
    uint256 internal _deployTimestamp;
    uint256 internal _devReward;
    uint256 internal _devVestingTime;
    uint256 internal _devWithdrawn;
    uint256 internal _cap;
    uint256 internal _lastRewardsTimestamp;
    uint256 internal _initialRewards;
    uint256 internal _rewardsPeriod;
    uint256 internal _epochDuration;

    function initialize(
        IAddressesProvider addressProvider,
        string calldata name,
        string calldata symbol,
        uint256 cap,
        uint256 epochDuration,
        address devAddress,
        uint256 devReward,
        uint256 devVestingTime,
        uint256 rewardsPeriod,
        uint256 initialRewards
    ) external initializer {
        __Ownable_init();
        __ERC20_init(name, symbol);
        _addressProvider = addressProvider;
        _cap = cap;
        _epochDuration = epochDuration;
        _deployTimestamp = block.timestamp;
        _devAddress = devAddress;
        _devReward = devReward;
        _devVestingTime = devVestingTime;
        _rewardsPeriod = rewardsPeriod;
        _initialRewards = initialRewards;
    }

    function getCap() public view virtual returns (uint256) {
        return _cap;
    }

    function distributeRewards() external {
        //The rewards can only be distributed if the rewards period has passed
        require(
            _lastRewardsTimestamp + _rewardsPeriod < block.timestamp,
            "Not enough time since last rewards distribution."
        );

        uint256 epoch = (block.timestamp - _deployTimestamp) / _epochDuration;
        _safeMint(
            _addressProvider.getNativeTokenVault(),
            (_initialRewards / epoch)
        );

        // Update last rewards tracker
        _lastRewardsTimestamp = block.timestamp;
    }

    function mint(address account, uint256 amount) external onlyOwner {
        _safeMint(account, amount);
    }

    function _safeMint(address account, uint256 amount) internal {
        require(
            ERC20Upgradeable.totalSupply() + amount <= getCap(),
            "NativeToken: cap exceeded"
        );
        _mint(account, amount);
    }

    function mintDevRewards(uint256 amount) external {
        // Require that the caller is the developer
        require(_msgSender() == _devAddress, "Caller must be dev");
        //Should only be able to withdrawn unvested tokens
        uint256 unvestedTokens;
        if (block.timestamp - _deployTimestamp < _devVestingTime) {
            unvestedTokens =
                _devReward *
                ((block.timestamp - _deployTimestamp) / _devVestingTime);
        } else {
            unvestedTokens = _devReward;
        }
        require(
            unvestedTokens >= amount + _devWithdrawn,
            "Amount bigger than allowed by vesting"
        );
        _safeMint(_devAddress, amount);
        _devWithdrawn += amount;
    }
}
