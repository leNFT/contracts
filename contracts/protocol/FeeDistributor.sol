// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.8.19;

import {IAddressProvider} from "../interfaces/IAddressProvider.sol";
import {IFeeDistributor} from "../interfaces/IFeeDistributor.sol";
import {IVotingEscrow} from "../interfaces/IVotingEscrow.sol";
import {SafeERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import {IERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import {IERC721Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC721/IERC721Upgradeable.sol";
import {DataTypes} from "../libraries/types/DataTypes.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";

/// @title FeeDistributor
/// @notice This contract distributes fees from the protocol to LE stakers, using the VotingEscrow interface to check the user's staked amount
contract FeeDistributor is IFeeDistributor, ReentrancyGuardUpgradeable {
    IAddressProvider private _addressProvider;
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

    /// @notice Initializes the contract with an addressProvider
    /// @param addressProvider addressProvider contract address
    function initialize(IAddressProvider addressProvider) external initializer {
        __ReentrancyGuard_init();
        _addressProvider = addressProvider;
    }

    /// @notice Retrieves the amount of fees for a given token in a given epoch
    /// @param token Token address
    /// @param epoch Epoch to retrieve fees from
    /// @return uint256 Amount of fees in the specified epoch
    function getTotalFeesAt(
        address token,
        uint256 epoch
    ) external view returns (uint256) {
        require(
            epoch <=
                IVotingEscrow(_addressProvider.getVotingEscrow()).getEpoch(
                    block.timestamp
                ),
            "FD:GTFA:FUTURE_EPOCH"
        );
        return _epochFees[token][epoch];
    }

    /// @notice Checks the balance of a token and updates the epoch fees for that token
    /// @param token Token address
    function checkpoint(address token) external override {
        // Find epoch we're in
        uint256 currentEpoch = IVotingEscrow(_addressProvider.getVotingEscrow())
            .getEpoch(block.timestamp);
        // Find the current balance of the token in question
        uint256 balance = IERC20Upgradeable(token).balanceOf(address(this));

        // Add unaccounted fees to current epoch
        _epochFees[token][currentEpoch] += balance - _accountedFees[token];

        // Update total fees accounted for
        _accountedFees[token] = balance;
    }

    /// @notice Allows anyone to retrieve any leftover rewards unclaimable by users and add them to the current epoch
    /// @param token Token address
    /// @param epoch Epoch to retrieve funds from
    function salvageFees(address token, uint256 epoch) external {
        IVotingEscrow votingEscrow = IVotingEscrow(
            _addressProvider.getVotingEscrow()
        );
        uint256 currentEpoch = votingEscrow.getEpoch(block.timestamp);
        // Must be a past epoch
        require(epoch < currentEpoch, "FD:SV:NOT_PAST_EPOCH");
        // Funds are only salvageable if the vote weight of the epoch in question is 0
        require(
            votingEscrow.getTotalWeightAt(epoch) == 0,
            "FD:SV:CLAIMABLE_FUNDS"
        );
        // There needs to be funds to salvage
        require(_epochFees[token][epoch] > 0, "FD:SV:NO_FUNDS");

        // Transfer rewards to current epoch
        _epochFees[token][currentEpoch] += _epochFees[token][epoch];

        emit SalvageFees(token, epoch, _epochFees[token][epoch]);

        delete _epochFees[token][epoch];
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

        // Make sure the lock exists
        require(
            IERC721Upgradeable(address(votingEscrow)).ownerOf(tokenId) !=
                address(0),
            "FD:C:LOCK_NOT_FOUND"
        );

        // Check if user has any user actions and therefore possibly something to claim
        if (votingEscrow.getLockHistoryLength(tokenId) == 0) {
            return 0;
        }

        // Set the next claimable epoch if it's the first time the user claims
        if (_lockNextClaimableEpoch[token][tokenId] == 0) {
            _lockNextClaimableEpoch[token][tokenId] =
                votingEscrow.getEpoch(
                    votingEscrow.getLockHistoryPoint(tokenId, 0).timestamp
                ) +
                1;
        }

        {
            // Iterate over a max of 50 epochs and/or user epochs
            DataTypes.Point memory lockHistoryPoint;
            uint256 lockHistoryPointer;
            uint256 nextClaimableEpoch;
            uint256 nextClaimableEpochTimestamp;
            uint256 nextPointEpoch;
            for (uint i = 0; i < 50; i++) {
                nextClaimableEpoch = _lockNextClaimableEpoch[token][tokenId];
                // Break if the next claimable epoch is the one we are in
                if (
                    nextClaimableEpoch >= votingEscrow.getEpoch(block.timestamp)
                ) {
                    break;
                } else {
                    // Get the current user history point
                    lockHistoryPointer = _lockHistoryPointer[token][tokenId];
                    lockHistoryPoint = votingEscrow.getLockHistoryPoint(
                        tokenId,
                        lockHistoryPointer
                    );

                    // Get the user's next claimable epoch and its timestamp
                    nextClaimableEpochTimestamp = votingEscrow
                        .getEpochTimestamp(nextClaimableEpoch);

                    // Check if the user entire activity history has been iterated
                    if (
                        lockHistoryPointer ==
                        votingEscrow.getLockHistoryLength(tokenId) - 1
                    ) {
                        // Sum claimable amount if its the last activity
                        if (
                            votingEscrow.getTotalWeightAt(nextClaimableEpoch) >
                            0
                        ) {
                            amountToClaim +=
                                (_epochFees[token][nextClaimableEpoch] *
                                    (lockHistoryPoint.bias -
                                        lockHistoryPoint.slope *
                                        (nextClaimableEpochTimestamp -
                                            lockHistoryPoint.timestamp))) /
                                votingEscrow.getTotalWeightAt(
                                    nextClaimableEpoch
                                );
                        }

                        // Increment next claimable epoch
                        _lockNextClaimableEpoch[token][tokenId]++;
                    } else {
                        // Find the epoch of the next user history point
                        nextPointEpoch = votingEscrow.getEpoch(
                            votingEscrow
                                .getLockHistoryPoint(
                                    tokenId,
                                    lockHistoryPointer + 1
                                )
                                .timestamp
                        );
                        if (
                            nextPointEpoch ==
                            votingEscrow.getEpoch(lockHistoryPoint.timestamp)
                        ) {
                            // If the next user activity is in the same epoch we increase the pointer
                            _lockHistoryPointer[token][tokenId]++;
                        } else {
                            // If the next user activity is in a different epoch we sum the claimable amount for his epoch
                            if (
                                votingEscrow.getTotalWeightAt(
                                    nextClaimableEpoch
                                ) > 0
                            ) {
                                amountToClaim +=
                                    (_epochFees[token][nextClaimableEpoch] *
                                        (lockHistoryPoint.bias -
                                            lockHistoryPoint.slope *
                                            (nextClaimableEpochTimestamp -
                                                lockHistoryPoint.timestamp))) /
                                    votingEscrow.getTotalWeightAt(
                                        nextClaimableEpoch
                                    );
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
        }

        if (amountToClaim > 0) {
            IERC20Upgradeable(token).safeTransfer(
                IERC721Upgradeable(_addressProvider.getVotingEscrow()).ownerOf(
                    tokenId
                ),
                amountToClaim
            );

            emit ClaimBribes(msg.sender, token, tokenId, amountToClaim);
        }
    }

    /// @notice Allows a user to claim their rewards from multiple locks for a specific token
    /// @param token Token address
    /// @param tokensIds the token ids of the locks
    /// @return amountToClaim uint256 Amount of rewards claimed
    function claimBatch(
        address token,
        uint256[] calldata tokensIds
    ) external returns (uint256 amountToClaim) {
        for (uint256 i = 0; i < tokensIds.length; i++) {
            amountToClaim += claim(token, tokensIds[i]);
        }
    }
}
