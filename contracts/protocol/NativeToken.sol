// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.8.17;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {ERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {IAddressesProvider} from "../interfaces/IAddressesProvider.sol";
import {INativeToken} from "../interfaces/INativeToken.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "hardhat/console.sol";
import {TrustusUpgradable} from "./Trustus/TrustusUpgradable.sol";
import {DataTypes} from "../libraries/types/DataTypes.sol";

contract NativeToken is
    Initializable,
    INativeToken,
    ERC20Upgradeable,
    OwnableUpgradeable,
    ReentrancyGuardUpgradeable,
    TrustusUpgradable
{
    IAddressesProvider private _addressProvider;
    address private _devAddress;
    uint256 internal _deployTimestamp;
    uint256 internal _devReward;
    uint256 internal _devVestingTime;
    uint256 internal _devWithdrawn;
    uint256 internal _cap;

    function initialize(
        IAddressesProvider addressProvider,
        string calldata name,
        string calldata symbol,
        uint256 cap,
        address devAddress,
        uint256 devReward,
        uint256 devVestingTime
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

    function mintGenesisTokens(address receiver, uint256 amount) external {
        require(
            msg.sender == _addressProvider.getGenesisNFT(),
            "Genesis tokens can only be minted by the Genesis NFT contract"
        );
        _mintTokens(receiver, amount);
    }

    function mintStakingRewardTokens(uint256 amount) external {
        require(
            msg.sender == _addressProvider.getNativeTokenVault(),
            "Vault rewards can only be miinted by the vault contract"
        );
        _mintTokens(_addressProvider.getNativeTokenVault(), amount);
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
        require(msg.sender == _devAddress, "Caller must be dev");

        //Should only be able to withdrawn unvested tokens
        require(
            getDevRewardTokens() >= amount,
            "Amount bigger than allowed by vesting"
        );
        _mintTokens(_devAddress, amount);
        _devWithdrawn += amount;
    }

    function mintAirdropTokens(bytes32 request, TrustusPacket calldata packet)
        external
        verifyPacket(request, packet)
    {
        DataTypes.AirdropTokens memory airdropParams = abi.decode(
            packet.payload,
            (DataTypes.AirdropTokens)
        );
        // Make sure the request is for the right token
        require(
            msg.sender == airdropParams.user,
            "Request user and caller don't coincide"
        );

        _mintTokens(airdropParams.user, airdropParams.amount);
    }

    function setTrustedAirdropSigner(address signer, bool isTrusted)
        external
        onlyOwner
    {
        _setIsTrusted(signer, isTrusted);
    }

    function isTrustedSigner(address signer) external view returns (bool) {
        return (_isTrusted(signer));
    }
}
