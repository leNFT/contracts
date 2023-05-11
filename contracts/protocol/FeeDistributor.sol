// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.8.19;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {IAddressesProvider} from "../interfaces/IAddressesProvider.sol";
import {IFeeDistributor} from "../interfaces/IFeeDistributor.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {ContextUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ContextUpgradeable.sol";
import {IVotingEscrow} from "../interfaces/IVotingEscrow.sol";
import {SafeERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import {IERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import {IERC721Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC721/IERC721Upgradeable.sol";
import {DataTypes} from "../libraries/types/DataTypes.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";

/// @title FeeDistributor
/// @notice This contract distributes fees from the protocol to LE stakers, using the VotingEscrow interface to check the user's staked amount
contract FeeDistributor is
    Initializable,
    ContextUpgradeable,
    OwnableUpgradeable,
    IFeeDistributor,
    ReentrancyGuardUpgradeable
{
    IAddressesProvider private _addressProvider;
    // Token + Lock token id = Epoch
    mapping(address => mapping(uint256 => uint256)) private _lockHistoryPointer;
    // Token + Epoch = Amount
    mapping(address => mapping(uint256 => uint256)) private _epochFees;
    mapping(address => mapping(uint256 => uint256))
        private _lockNextClaimableEpoch;
    // Token + epoch = amount
    mapping(address => uint256) private _accountedFees;

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
        __ReentrancyGuard_init();
        __Ownable_init();
        _addressProvider = addressProvider;
    }

    /// @notice Retrieves the amount of fees for a given token in a given epoch
    /// @param token Token address
    /// @param epoch Epoch to retrieve fees from
    /// @return uint256 Amount of fees in the specified epoch
    function totalFeesAt(
        address token,
        uint256 epoch
    ) external view returns (uint256) {
        return _epochFees[token][epoch];
    }

    /// @notice Checks the balance of a token and updates the epoch fees for that token
    /// @param token Token address
    function checkpoint(address token) external override {
        // Find epoch we're in
        uint256 epoch = IVotingEscrow(_addressProvider.getVotingEscrow()).epoch(
            block.timestamp
        );
        // Find the current balance if the token in question
        uint256 balance = IERC20Upgradeable(token).balanceOf(address(this));

        // Add unaccounted fees to current epoch
        _epochFees[token][epoch] += balance - _accountedFees[token];

        // Update total fees accounted for
        _accountedFees[token] = balance;
    }

    /// @notice Allows anyone to retrieve any leftover rewards unclaimable by users and add them to the current epoch
    /// @param token Token address
    /// @param epoch Epoch to retrieve funds from
    function salvageRewards(address token, uint256 epoch) external {
        IVotingEscrow votingEscrow = IVotingEscrow(
            _addressProvider.getVotingEscrow()
        );
        // Funds not claimable by users are epoch in which there was no locked supply
        require(
            votingEscrow.totalWeightAt(epoch) == 0,
            "FD:SV:FUNDS_CLAIMABLE"
        );
        // THere needs to be funds to salvage
        require(_epochFees[token][epoch] > 0, "FD:SV:NO_FUNDS");

        // Tranfer rewards to current epoch
        _epochFees[token][votingEscrow.epoch(block.timestamp)] += _epochFees[
            token
        ][epoch];

        delete _epochFees[token][epoch];
    }

    /// @notice Returns the next claimable epoch for a user
    /// @param token Token address to claim for
    /// @param tokenId the token id of the lock
    /// @return uint256 Next claimable epoch
    function lockNextClaimableEpoch(
        address token,
        uint256 tokenId
    ) external view returns (uint256) {
        return _lockNextClaimableEpoch[token][tokenId];
    }

    /// @notice Allows a user to claim their rewards from a lock for a specific token
    /// @param token Token address
    /// @param tokenId the token id of the lock
    /// @return amountToClaim Amount of rewards claimed
    function claim(
        address token,
        uint256 tokenId
    ) public nonReentrant returns (uint256 amountToClaim) {
        IVotingEscrow votingEscrow = IVotingEscrow(
            _addressProvider.getVotingEscrow()
        );

        // Check if user has any user actions and therefore possibly something to claim
        if (votingEscrow.lockHistoryLength(tokenId) == 0) {
            return 0;
        }

        // Set the next claimable epoch if it's the first time the user claims
        if (_lockNextClaimableEpoch[token][tokenId] == 0) {
            _lockNextClaimableEpoch[token][tokenId] =
                votingEscrow.epoch(
                    votingEscrow.getLockHistoryPoint(tokenId, 0).timestamp
                ) +
                1;
        }

        // Iterate over a max of 50 epochs and/or user epochs
        DataTypes.Point memory lockHistoryPoint;
        uint256 nextClaimableEpoch;
        uint256 nextClaimableEpochTimestamp;
        uint256 nextPointEpoch;
        for (uint i = 0; i < 50; i++) {
            nextClaimableEpoch = _lockNextClaimableEpoch[token][tokenId];
            // Break if the next claimable epoch is the one we are in
            if (nextClaimableEpoch >= votingEscrow.epoch(block.timestamp)) {
                break;
            } else {
                // Get the current user history point
                lockHistoryPoint = votingEscrow.getLockHistoryPoint(
                    tokenId,
                    _lockHistoryPointer[token][tokenId]
                );

                // Get the user's next claimable epoch and its timestamp
                nextClaimableEpochTimestamp = votingEscrow.epochTimestamp(
                    nextClaimableEpoch
                );

                // Check if the user entire activity history has been iterated
                if (
                    _lockHistoryPointer[token][tokenId] ==
                    votingEscrow.lockHistoryLength(tokenId) - 1
                ) {
                    // Sum claimable amount if its the last activity
                    if (votingEscrow.totalWeightAt(nextClaimableEpoch) > 0) {
                        amountToClaim +=
                            (_epochFees[token][nextClaimableEpoch] *
                                (lockHistoryPoint.bias -
                                    lockHistoryPoint.slope *
                                    (nextClaimableEpochTimestamp -
                                        lockHistoryPoint.timestamp))) /
                            votingEscrow.totalWeightAt(nextClaimableEpoch);
                    }

                    // Increment next claimable epoch
                    _lockNextClaimableEpoch[token][tokenId]++;
                } else {
                    // Find the epoch of the next user history point
                    nextPointEpoch = votingEscrow.epoch(
                        votingEscrow
                            .getLockHistoryPoint(
                                tokenId,
                                _lockHistoryPointer[token][tokenId] + 1
                            )
                            .timestamp
                    );
                    if (
                        nextPointEpoch ==
                        votingEscrow.epoch(lockHistoryPoint.timestamp)
                    ) {
                        // If the next user activity is in the same epoch we increase the pointer
                        _lockHistoryPointer[token][tokenId]++;
                    } else {
                        // If the next user activity is in a different epoch we sum the claimable amount for his epoch
                        if (
                            votingEscrow.totalWeightAt(nextClaimableEpoch) > 0
                        ) {
                            amountToClaim +=
                                (_epochFees[token][nextClaimableEpoch] *
                                    (lockHistoryPoint.bias -
                                        lockHistoryPoint.slope *
                                        (nextClaimableEpochTimestamp -
                                            lockHistoryPoint.timestamp))) /
                                votingEscrow.totalWeightAt(nextClaimableEpoch);
                        }

                        // If the next user activity is in the next claimable epoch we increase the user history pointer
                        if (nextPointEpoch == nextClaimableEpoch) {
                            _lockHistoryPointer[token][tokenId]++;
                        }

                        // Increment next claimable epoch
                        _lockNextClaimableEpoch[token][tokenId]++;
                    }
                }
            }
        }

        IERC20Upgradeable(token).safeTransfer(
            IERC721Upgradeable(_addressProvider.getVotingEscrow()).ownerOf(
                tokenId
            ),
            amountToClaim
        );
    }

    /// @notice Allows a user to claim their rewards from multiple locks for a specific token
    /// @param token Token address
    /// @param tokensIds the token ids of the locks
    /// @return amountToClaim uint256 Amount of rewards claimed
    function claimBatch(
        address token,
        uint256[] calldata tokensIds
    ) external nonReentrant returns (uint256 amountToClaim) {
        for (uint256 i = 0; i < tokensIds.length; i++) {
            amountToClaim += claim(token, tokensIds[i]);
        }
    }
}
