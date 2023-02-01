// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.8.17;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {IAddressesProvider} from "../interfaces/IAddressesProvider.sol";
import {IFeeDistributor} from "../interfaces/IFeeDistributor.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {ContextUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ContextUpgradeable.sol";
import {IVotingEscrow} from "../interfaces/IVotingEscrow.sol";
import {SafeERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import {IERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import {Time} from "../libraries/Time.sol";
import {DataTypes} from "../libraries/types/DataTypes.sol";
import "hardhat/console.sol";

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
        private _userNextClaimedEpoch;
    mapping(address => uint256) private _totalFees;

    using SafeERC20Upgradeable for IERC20Upgradeable;

    function initialize(
        IAddressesProvider addressProvider
    ) external initializer {
        __Ownable_init();
        _addressProvider = addressProvider;
    }

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

    function claim(address token) external override returns (uint256) {
        IVotingEscrow votingEscrow = IVotingEscrow(
            _addressProvider.getVotingEscrow()
        );

        // Check if user has any user actions and therefore possibly something to claim
        if (votingEscrow.userHistoryLength(msg.sender) == 0) {
            return 0;
        }

        // Set the next claimable epoch if it's the first time the user claims
        if (_userNextClaimedEpoch[token][msg.sender] == 0) {
            _userNextClaimedEpoch[token][msg.sender] =
                votingEscrow.epoch(
                    votingEscrow.getUserHistoryPoint(msg.sender, 0).timestamp
                ) +
                1;
        }

        // Iterate over a max of 50 weeks and/or user epochs
        uint256 amountToClaim;
        DataTypes.Point memory userHistoryPoint;
        uint256 nextClaimedEpoch;
        uint256 nextClaimedEpochTimestamp;
        uint256 nextPointEpoch;
        for (uint i = 0; i < 50; i++) {
            nextClaimedEpoch = _userNextClaimedEpoch[token][msg.sender];
            // Break if the next claimable epoch is the one we are in
            if (nextClaimedEpoch >= votingEscrow.epoch(block.timestamp)) {
                break;
            } else {
                // Get the current user history point
                userHistoryPoint = votingEscrow.getUserHistoryPoint(
                    msg.sender,
                    _userHistoryPointer[token][msg.sender]
                );

                // Get the user's next claimable epoch and its timestamp
                nextClaimedEpochTimestamp = votingEscrow.epochTimestamp(
                    nextClaimedEpoch
                );

                // Check if the user entire activity history has been iterated
                if (
                    _userHistoryPointer[token][msg.sender] ==
                    votingEscrow.userHistoryLength(msg.sender) - 1
                ) {
                    // Sum claimable amount if its the last activity
                    if (votingEscrow.totalSupplyAt(nextClaimedEpoch) != 0) {
                        amountToClaim +=
                            (_epochFees[token][nextClaimedEpoch] *
                                (userHistoryPoint.bias -
                                    userHistoryPoint.slope *
                                    (nextClaimedEpochTimestamp -
                                        userHistoryPoint.timestamp))) /
                            votingEscrow.totalSupplyAt(nextClaimedEpoch);
                    }

                    // Increment next claimable epoch
                    _userNextClaimedEpoch[token][msg.sender]++;
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
                    if (
                        nextPointEpoch ==
                        votingEscrow.epoch(userHistoryPoint.timestamp)
                    ) {
                        // If the next user activity is in the same epoch we increase the pointer
                        _userHistoryPointer[token][msg.sender]++;
                    } else {
                        // If the next user activity is in a different epoch we sum the claimable amount for his epoch
                        if (votingEscrow.totalSupplyAt(nextClaimedEpoch) != 0) {
                            amountToClaim +=
                                (_epochFees[token][nextClaimedEpoch] *
                                    (userHistoryPoint.bias -
                                        userHistoryPoint.slope *
                                        (nextClaimedEpochTimestamp -
                                            userHistoryPoint.timestamp))) /
                                votingEscrow.totalSupplyAt(nextClaimedEpoch);
                        }

                        // Increment next claimable epoch
                        _userNextClaimedEpoch[token][msg.sender]++;
                        // If the next user activity is in the next epoch to claim we increase the user history pointer
                        if (
                            nextPointEpoch ==
                            _userNextClaimedEpoch[token][msg.sender]
                        ) {
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
