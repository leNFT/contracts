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
import {DataTypes} from "../libraries/types/DataTypes.sol";
import "hardhat/console.sol";

/// @title FeeDistributor
/// @notice This contract distributes fees from the protocol to the stakers of the respective token, using the VotingEscrow interface to check the user's staked amount
contract FeeDistributor is
    Initializable,
    ContextUpgradeable,
    OwnableUpgradeable,
    IFeeDistributor
{
    IAddressesProvider private _addressProvider;
    mapping(address => mapping(address => uint256)) private _userHistoryPointer;
    mapping(address => mapping(uint256 => uint256)) private _epochFees;
    mapping(address => mapping(address => uint256))
        private _userNextClaimableEpoch;
    mapping(address => uint256) private _totalFees;

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
        _epochFees[token][epoch] += balance - _totalFees[token];

        // Update total fees accounted for
        _totalFees[token] = balance;
    }

    /// @notice Allows the owner to retrieve any leftover rewards not claimable by users
    /// @param token Token address
    /// @param epoch Epoch to retrieve funds from
    function salvageRewards(address token, uint256 epoch) external {
        IVotingEscrow votingEscrow = IVotingEscrow(
            _addressProvider.getVotingEscrow()
        );
        // Funds not claimable by users are epoch in which there was no locked supply
        require(
            votingEscrow.totalSupplyAt(epoch) == 0,
            "Funds are claimable by users"
        );
        // THere needs to be funds to salvage
        require(_epochFees[token][epoch] > 0, "No funds left to salvage");

        // Tranfer rewards to current epoch
        _epochFees[token][epoch] += _epochFees[token][
            votingEscrow.epoch(block.timestamp)
        ];

        // Reset epoch fees so they can't be salvaged again
        _epochFees[token][epoch] = 0;
    }

    /// @notice Returns the next claimable epoch for a user
    /// @param token Token address to claim for
    /// @param user User address
    /// @return uint256 Next claimable epoch
    function userNextClaimableEpoch(
        address token,
        address user
    ) external view returns (uint256) {
        return _userNextClaimableEpoch[token][user];
    }

    /// @notice Allows a user to claim their rewards for a specific token
    /// @param token Token address
    /// @return uint256 Amount of rewards claimed
    function claim(address token) external override returns (uint256) {
        console.log("claiming");
        IVotingEscrow votingEscrow = IVotingEscrow(
            _addressProvider.getVotingEscrow()
        );

        // Check if user has any user actions and therefore possibly something to claim
        if (votingEscrow.userHistoryLength(msg.sender) == 0) {
            return 0;
        }

        // Set the next claimable epoch if it's the first time the user claims
        if (_userNextClaimableEpoch[token][msg.sender] == 0) {
            _userNextClaimableEpoch[token][msg.sender] =
                votingEscrow.epoch(
                    votingEscrow.getUserHistoryPoint(msg.sender, 0).timestamp
                ) +
                1;
        }

        // Iterate over a max of 50 epochs and/or user epochs
        uint256 amountToClaim;
        DataTypes.Point memory userHistoryPoint;
        uint256 nextClaimableEpoch;
        uint256 nextClaimableEpochTimestamp;
        uint256 nextPointEpoch;
        console.log("epoch", votingEscrow.epoch(block.timestamp));
        for (uint i = 0; i < 50; i++) {
            nextClaimableEpoch = _userNextClaimableEpoch[token][msg.sender];
            console.log("nextClaimableEpoch", nextClaimableEpoch);
            // Break if the next claimable epoch is the one we are in
            if (nextClaimableEpoch >= votingEscrow.epoch(block.timestamp)) {
                break;
            } else {
                // Get the current user history point
                userHistoryPoint = votingEscrow.getUserHistoryPoint(
                    msg.sender,
                    _userHistoryPointer[token][msg.sender]
                );

                // Get the user's next claimable epoch and its timestamp
                nextClaimableEpochTimestamp = votingEscrow.epochTimestamp(
                    nextClaimableEpoch
                );

                // Check if the user entire activity history has been iterated
                if (
                    _userHistoryPointer[token][msg.sender] ==
                    votingEscrow.userHistoryLength(msg.sender) - 1
                ) {
                    // Sum claimable amount if its the last activity
                    if (votingEscrow.totalSupplyAt(nextClaimableEpoch) > 0) {
                        console.log("nextClaimableEpoch", nextClaimableEpoch);
                        console.log(
                            "nextClaimableEpochTimestamp",
                            nextClaimableEpochTimestamp
                        );
                        console.log(
                            "userHistoryPoint.timestamp",
                            userHistoryPoint.timestamp
                        );
                        amountToClaim +=
                            (_epochFees[token][nextClaimableEpoch] *
                                (userHistoryPoint.bias -
                                    userHistoryPoint.slope *
                                    (nextClaimableEpochTimestamp -
                                        userHistoryPoint.timestamp))) /
                            votingEscrow.totalSupplyAt(nextClaimableEpoch);
                    }

                    // Increment next claimable epoch
                    _userNextClaimableEpoch[token][msg.sender]++;
                } else {
                    // Find the epoch of the next user history point
                    nextPointEpoch = votingEscrow.epoch(
                        votingEscrow
                            .getUserHistoryPoint(
                                msg.sender,
                                _userHistoryPointer[token][msg.sender] + 1
                            )
                            .timestamp
                    );
                    console.log("nextPointEpoch", nextPointEpoch);
                    if (
                        nextPointEpoch ==
                        votingEscrow.epoch(userHistoryPoint.timestamp)
                    ) {
                        // If the next user activity is in the same epoch we increase the pointer
                        _userHistoryPointer[token][msg.sender]++;
                    } else {
                        // If the next user activity is in a different epoch we sum the claimable amount for his epoch
                        if (
                            votingEscrow.totalSupplyAt(nextClaimableEpoch) > 0
                        ) {
                            amountToClaim +=
                                (_epochFees[token][nextClaimableEpoch] *
                                    (userHistoryPoint.bias -
                                        userHistoryPoint.slope *
                                        (nextClaimableEpochTimestamp -
                                            userHistoryPoint.timestamp))) /
                                votingEscrow.totalSupplyAt(nextClaimableEpoch);
                        }

                        // Increment next claimable epoch
                        _userNextClaimableEpoch[token][msg.sender]++;
                        // If the next user activity is in the next epoch to claim we increase the user history pointer
                        if (
                            nextPointEpoch + 1 ==
                            _userNextClaimableEpoch[token][msg.sender]
                        ) {
                            console.log("incrementing");
                            _userHistoryPointer[token][msg.sender]++;
                        }
                    }
                }
            }
        }

        IERC20Upgradeable(token).safeTransfer(_msgSender(), amountToClaim);

        return amountToClaim;
    }
}
