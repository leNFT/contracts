// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.8.19;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {IAddressesProvider} from "../interfaces/IAddressesProvider.sol";
import {IGaugeController} from "../interfaces/IGaugeController.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {ContextUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ContextUpgradeable.sol";
import {IVotingEscrow} from "../interfaces/IVotingEscrow.sol";
import {SafeERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import {IERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import {IERC721Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC721/IERC721Upgradeable.sol";
import {DataTypes} from "../libraries/types/DataTypes.sol";
import {IBribes} from "../interfaces/IBribes.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "hardhat/console.sol";

/// @title Bribes contract
/// @notice Allows users to bribe the veLE token holders in order to incentivize them to vote for a specific gauge
contract Bribes is
    Initializable,
    ContextUpgradeable,
    OwnableUpgradeable,
    IBribes,
    ReentrancyGuardUpgradeable
{
    IAddressesProvider private _addressProvider;
    // Token + Gauge + Epoch = Amount
    mapping(address => mapping(address => mapping(uint256 => uint256)))
        private _gaugeBribes;
    // Token + Gauge + Epoch +User = Bribe
    mapping(address => mapping(address => mapping(uint256 => mapping(address => uint256))))
        private _userBribes;
    //Token -> Gauge -> TokenId -> Epoch
    mapping(address => mapping(address => mapping(uint256 => uint256)))
        private _voteNextClaimableEpoch;

    using SafeERC20Upgradeable for IERC20Upgradeable;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// @notice Initializes the contract with an AddressesProvider
    /// @param addressProvider AddressesProvider contract address
    function initialize(
        IAddressesProvider addressProvider
    ) external initializer {
        __Ownable_init();
        _addressProvider = addressProvider;
    }

    /// @notice Deposits a bribe for a specific gauge
    /// @param briber The account to deposit the bribe for
    /// @param token The token to bribe with
    /// @param gauge The gauge to bribe
    /// @param amount The amount to bribe with
    function depositBribe(
        address briber,
        address token,
        address gauge,
        uint256 amount
    ) external override nonReentrant {
        // Find what's the next epoch
        uint256 nextEpoch = IVotingEscrow(_addressProvider.getVotingEscrow())
            .epoch(block.timestamp) + 1;

        // Add the amount to the bribes
        _gaugeBribes[token][gauge][nextEpoch] += amount;
        _userBribes[token][gauge][nextEpoch][briber] += amount;

        // Transfer the bribe tokens to this contract
        IERC20Upgradeable(token).safeTransferFrom(
            msg.sender,
            address(this),
            amount
        );
    }

    /// @notice Withdraws a bribe for a specific gauge
    /// @dev Only works before the bribe's epoch has started
    /// @param receiver The account to receive the bribe back
    /// @param token The token to withdraw the bribe from
    /// @param gauge The gauge to withdraw the bribe from
    /// @param amount The amount to withdraw
    function withdrawBribe(
        address receiver,
        address token,
        address gauge,
        uint256 amount
    ) external override nonReentrant {
        // Find what's the next epoch
        uint256 nextEpoch = IVotingEscrow(_addressProvider.getVotingEscrow())
            .epoch(block.timestamp) + 1;

        // Make sure there are enough funds to withdraw
        require(
            _userBribes[token][gauge][nextEpoch][msg.sender] >= amount,
            "Not enough funds to withdraw"
        );

        // Subtract the amount from the bribes
        _gaugeBribes[token][gauge][nextEpoch] -= amount;
        _userBribes[token][gauge][nextEpoch][msg.sender] -= amount;

        // Transfer the bribe tokens back to the user
        IERC20Upgradeable(token).safeTransfer(receiver, amount);
    }

    /// @notice Get bribes back if no user voted for the gauge
    /// @dev Only works after the bribe's epoch has started
    /// @param token The token to salvage the bribe from
    /// @param gauge The gauge to salvage the bribe from
    function salvageBribes(
        address token,
        address gauge,
        uint256 epoch
    ) external nonReentrant {
        IGaugeController gaugeController = IGaugeController(
            _addressProvider.getGaugeController()
        );
        require(
            epoch <=
                IVotingEscrow(_addressProvider.getVotingEscrow()).epoch(
                    block.timestamp
                ),
            "Epoch is in the future"
        );
        // Funds not claimable by users are epoch in which there was no voting power for gauge
        require(
            gaugeController.getGaugeWeightAt(gauge, epoch) == 0,
            "Bribes are claimable by users"
        );

        // THere needs to be funds to salvage
        require(
            _userBribes[token][gauge][epoch][msg.sender] > 0,
            "No funds to salvage"
        );

        // Tranfer bribe back to briber
        IERC20Upgradeable(token).safeTransfer(
            msg.sender,
            _userBribes[token][gauge][epoch][msg.sender]
        );

        // Subtract the amount from the bribes
        _gaugeBribes[token][gauge][epoch] -= _userBribes[token][gauge][epoch][
            msg.sender
        ];
        _userBribes[token][gauge][epoch][msg.sender] = 0;
    }

    /// @notice Get bribes from a user for a specific gauge in a specific epoch
    /// @param token The token to get the bribes for
    /// @param gauge The gauge to get the bribes for
    /// @param epoch The epoch to get the bribes for
    /// @param user The user to get the bribes for
    function getUserBribes(
        address token,
        address gauge,
        uint256 epoch,
        address user
    ) external view returns (uint256) {
        return _userBribes[token][gauge][epoch][user];
    }

    /// @notice Get bribes for a specific gauge in a specific epoch
    /// @param token The token to get the bribes for
    /// @param gauge The gauge to get the bribes for
    /// @param epoch The epoch to get the bribes for
    function getGaugeBribes(
        address token,
        address gauge,
        uint256 epoch
    ) external view returns (uint256) {
        return _gaugeBribes[token][gauge][epoch];
    }

    /// @notice Claim bribes for a specific gauge
    /// @dev Max epochs to claim is 50
    /// @param token The token to claim the bribes for
    /// @param gauge The gauge to claim the bribes for
    /// @param tokenId The tokenid of the lock to claim the bribes for
    function claim(
        address token,
        address gauge,
        uint256 tokenId
    ) external nonReentrant returns (uint256) {
        // Make sure the caller is the owner of the token
        require(
            IERC721Upgradeable(_addressProvider.getVotingEscrow()).ownerOf(
                tokenId
            ) == msg.sender,
            "Caller is not the owner of the token"
        );

        // Get lock vote point and its epoch
        DataTypes.Point memory lockLastPoint = IGaugeController(
            _addressProvider.getGaugeController()
        ).lockVotePointForGauge(tokenId, gauge);

        // Make sure the token has voting power for the gauge
        if (lockLastPoint.bias == 0) {
            return 0;
        }

        // Find epoch we're in
        uint256 currentEpoch = IVotingEscrow(_addressProvider.getVotingEscrow())
            .epoch(block.timestamp);
        uint256 lockLastPointEpoch = IVotingEscrow(
            _addressProvider.getVotingEscrow()
        ).epoch(lockLastPoint.timestamp);

        // Bring the next claimable epoch up to date if needed
        if (
            _voteNextClaimableEpoch[token][gauge][tokenId] <= lockLastPointEpoch
        ) {
            _voteNextClaimableEpoch[token][gauge][tokenId] =
                lockLastPointEpoch +
                1;
        }

        // Iterate over a max of 50 epochs
        uint256 amountToClaim = 0;
        for (uint i = 0; i < 50; i++) {
            // Break if we're at the current epoch or higher
            uint256 epoch = _voteNextClaimableEpoch[token][gauge][tokenId];
            if (epoch > currentEpoch) {
                break;
            }

            uint256 epochTimestamp = IVotingEscrow(
                _addressProvider.getVotingEscrow()
            ).epochTimestamp(epoch);

            uint256 lockWeightAtEpoch = lockLastPoint.bias -
                (lockLastPoint.slope *
                    (epochTimestamp - lockLastPoint.timestamp));

            uint256 gaugeWeightAtEpoch = IGaugeController(
                _addressProvider.getGaugeController()
            ).getGaugeWeightAt(gauge, epoch);

            // Increment amount to claim
            amountToClaim +=
                (_gaugeBribes[token][gauge][epoch] * lockWeightAtEpoch) /
                gaugeWeightAtEpoch;

            // Increment epoch
            _voteNextClaimableEpoch[token][gauge][tokenId]++;
        }

        // Transfer claim to user
        IERC20Upgradeable(token).safeTransfer(msg.sender, amountToClaim);

        return amountToClaim;
    }
}
