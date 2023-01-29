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
import {TrustusUpgradable} from "./Trustus/TrustusUpgradable.sol";
import {ContextUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ContextUpgradeable.sol";
import {DataTypes} from "../libraries/types/DataTypes.sol";
import {Time} from "../libraries/Time.sol";

contract NativeToken is
    Initializable,
    ContextUpgradeable,
    INativeToken,
    ERC20Upgradeable,
    OwnableUpgradeable,
    ReentrancyGuardUpgradeable,
    TrustusUpgradable
{
    IAddressesProvider private _addressProvider;
    address private _devAddress;
    uint256 private _deployTimestamp;
    uint256 private _devReward;
    uint256 private _devVestingTime;
    uint256 private _devWithdrawn;
    uint256 private _cap;
    uint256 private _initialRewards;

    // Mapping of airdroped users
    mapping(address => bool) private mintedAirdrop;

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
        __Trustus_init();
        __ERC20_init(name, symbol);
        _addressProvider = addressProvider;
        _cap = cap;
        _deployTimestamp = block.timestamp;
        _devAddress = devAddress;
        _devReward = devReward;
        _devVestingTime = devVestingTime;
        _initialRewards = initialRewards;
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

    function mintGenesisTokens(uint256 amount) external {
        require(
            _msgSender() == _addressProvider.getGenesisNFT(),
            "Genesis tokens can only be minted by the Genesis NFT contract"
        );
        _mintTokens(_addressProvider.getGenesisNFT(), amount);
    }

    function getEpochRewards(
        uint256 epoch
    ) external view override returns (uint256) {
        uint256 inflationEpoch = epoch / Time.YEAR_IN_WEEKS;
        return _initialRewards / (2 ** inflationEpoch);
    }

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

    function mintAirdropTokens(
        bytes32 request,
        TrustusPacket calldata packet
    ) external verifyPacket(request, packet) {
        DataTypes.AirdropTokens memory airdropParams = abi.decode(
            packet.payload,
            (DataTypes.AirdropTokens)
        );
        // Make sure the request is for the right user
        require(
            _msgSender() == airdropParams.user,
            "Request user and caller don't coincide"
        );

        // Check if user hasn't received the airdrop before
        require(
            mintedAirdrop[airdropParams.user] == false,
            "User already minted airdrop"
        );

        //Mint airdrop tokens
        _mintTokens(airdropParams.user, airdropParams.amount);

        // Mark address airdrop done
        mintedAirdrop[airdropParams.user] = true;
    }

    function hasMintedAirdrop(address user) external view returns (bool) {
        return mintedAirdrop[user];
    }

    function setTrustedAirdropSigner(
        address signer,
        bool isTrusted
    ) external onlyOwner {
        _setIsTrusted(signer, isTrusted);
    }

    function isTrustedSigner(address signer) external view returns (bool) {
        return (_isTrusted(signer));
    }
}
