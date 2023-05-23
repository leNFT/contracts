// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.8.19;

import {IAddressProvider} from "../interfaces/IAddressProvider.sol";
import {IGaugeController} from "../interfaces/IGaugeController.sol";
import {IVotingEscrow} from "../interfaces/IVotingEscrow.sol";
import {SafeERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import {IERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import {IERC721Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC721/IERC721Upgradeable.sol";
import {DataTypes} from "../libraries/types/DataTypes.sol";
import {IBribes} from "../interfaces/IBribes.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";

/// @title Bribes contract
/// @notice Allows users to bribe the veLE token holders in order to incentivize them to vote for a specific gauge
contract Bribes is IBribes, ReentrancyGuardUpgradeable {
    IAddressProvider private _addressProvider;
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

    modifier validGauge(address gauge) {
        _requireValidGauge(gauge);
        _;
    }

    modifier noFutureEpoch(uint256 epoch) {
        _requireNoFutureEpoch(epoch);
        _;
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// @notice Initializes the contract with an addressProvider
    /// @param addressProvider addressProvider contract address
    function initialize(IAddressProvider addressProvider) external initializer {
        __ReentrancyGuard_init();
        _addressProvider = addressProvider;
    }

    /// @notice Deposits a bribe for a specific gauge for the next epoch
    /// @param briber The account hat will own the bribe
    /// @param token The token to bribe with
    /// @param gauge The gauge to bribe
    /// @param amount The amount to bribe with
    function depositBribe(
        address briber,
        address token,
        address gauge,
        uint256 amount
    ) external override validGauge(gauge) nonReentrant {
        require(amount > 0, "B:DB:ZERO_AMOUNT");
        // Find what's the next epoch
        uint256 nextEpoch = IVotingEscrow(_addressProvider.getVotingEscrow())
            .getEpoch(block.timestamp) + 1;

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
    ) external override validGauge(gauge) nonReentrant {
        require(amount > 0, "B:WB:ZERO_AMOUNT");
        // Find what's the next epoch
        uint256 nextEpoch = IVotingEscrow(_addressProvider.getVotingEscrow())
            .getEpoch(block.timestamp) + 1;

        // Make sure there are enough funds to withdraw
        require(
            _userBribes[token][gauge][nextEpoch][msg.sender] >= amount,
            "B:WB:NOT_ENOUGH_FUNDS"
        );

        // Subtract the amount from the bribes
        _gaugeBribes[token][gauge][nextEpoch] -= amount;
        _userBribes[token][gauge][nextEpoch][msg.sender] -= amount;

        // Transfer the bribe tokens back to the user
        IERC20Upgradeable(token).safeTransfer(receiver, amount);
    }

    /// @notice Get deposited bribes back if no user voted for the gauge
    /// @dev Only works after the next epoch has started
    /// @dev Anyone can do this
    /// @param token The token to salvage the bribe from
    /// @param gauge The gauge to salvage the bribe from
    /// @param epoch The epoch to salvage the bribe from
    function salvageBribes(
        address token,
        address gauge,
        uint256 epoch
    ) external nonReentrant validGauge(gauge) noFutureEpoch(epoch) {
        IGaugeController gaugeController = IGaugeController(
            _addressProvider.getGaugeController()
        );

        // Bribes are only salvageable if there were no votes for the gauge in the bribe's epoch
        require(
            gaugeController.getGaugeWeightAt(gauge, epoch) == 0,
            "B:SB:FUNDS_CLAIMABLE"
        );

        uint256 epochUserBribes = _userBribes[token][gauge][epoch][msg.sender];

        // THere needs to be funds to salvage
        require(epochUserBribes > 0, "B:SB:NO_FUNDS");

        // Tranfer bribe back to briber
        IERC20Upgradeable(token).safeTransfer(msg.sender, epochUserBribes);

        // Subtract the amount from the gauge bribes
        _gaugeBribes[token][gauge][epoch] -= epochUserBribes;

        // Clear the user bribes
        delete _userBribes[token][gauge][epoch][msg.sender];
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
    ) external view validGauge(gauge) returns (uint256) {
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
    ) external view validGauge(gauge) returns (uint256) {
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
    ) external validGauge(gauge) nonReentrant returns (uint256 amountToClaim) {
        address votingEscrow = _addressProvider.getVotingEscrow();
        // Make sure the caller is the owner of the token
        require(
            IERC721Upgradeable(votingEscrow).ownerOf(tokenId) == msg.sender,
            "B:C:NOT_OWNER"
        );

        IGaugeController gaugeController = IGaugeController(
            _addressProvider.getGaugeController()
        );

        // Get lock vote point and its epoch
        DataTypes.Point memory lockLastPoint = gaugeController
            .getLockVotePointForGauge(tokenId, gauge);

        // Make sure the token has voting power for the gauge
        if (lockLastPoint.bias == 0) {
            return 0;
        }

        // Bring the next claimable epoch up to date if needed
        if (
            _voteNextClaimableEpoch[token][gauge][tokenId] <=
            IVotingEscrow(votingEscrow).getEpoch(lockLastPoint.timestamp)
        ) {
            _voteNextClaimableEpoch[token][gauge][tokenId] =
                IVotingEscrow(votingEscrow).getEpoch(lockLastPoint.timestamp) +
                1;
        }

        // Find epoch we're in
        uint256 currentEpoch = IVotingEscrow(votingEscrow).getEpoch(
            block.timestamp
        );

        // Iterate over a max of 50 epochs
        uint256 epoch;
        uint256 gaugeWeightAtEpoch;

        for (uint i = 0; i < 50; i++) {
            // Break if we're at the current epoch or higher
            epoch = _voteNextClaimableEpoch[token][gauge][tokenId];
            if (epoch > currentEpoch) {
                break;
            }

            gaugeWeightAtEpoch = gaugeController.getGaugeWeightAt(gauge, epoch);
            if (gaugeWeightAtEpoch > 0) {
                // Increment amount to claim
                amountToClaim +=
                    (_gaugeBribes[token][gauge][epoch] *
                        (lockLastPoint.bias -
                            (lockLastPoint.slope *
                                (IVotingEscrow(votingEscrow).getEpochTimestamp(
                                    epoch
                                ) - lockLastPoint.timestamp)))) /
                    gaugeWeightAtEpoch;
            }

            // Increment epoch
            _voteNextClaimableEpoch[token][gauge][tokenId]++;
        }

        // Transfer claim to user
        if (amountToClaim > 0) {
            IERC20Upgradeable(token).safeTransfer(msg.sender, amountToClaim);
        }
    }

    function _requireValidGauge(address gauge) internal view {
        require(
            IGaugeController(_addressProvider.getGaugeController()).isGauge(
                gauge
            ),
            "B:INVALID_GAUGE"
        );
    }

    function _requireNoFutureEpoch(uint256 epoch) internal view {
        require(
            epoch <=
                IVotingEscrow(_addressProvider.getVotingEscrow()).getEpoch(
                    block.timestamp
                ),
            "B:FUTURE_EPOCH"
        );
    }
}
