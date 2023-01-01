//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;

import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {PercentageMath} from "../../libraries/math/PercentageMath.sol";
import {DataTypes} from "../../libraries/types/DataTypes.sol";
import {IVotingEscrow} from "../../interfaces/IVotingEscrow.sol";
import {IGaugeController} from "../../interfaces/IGaugeController.sol";
import {IAddressesProvider} from "../../interfaces/IAddressesProvider.sol";
import {Time} from "../../libraries/Time.sol";

contract GaugeController is OwnableUpgradeable, IGaugeController {
    IAddressesProvider private _addressProvider;

    // Epoch history of gauge vote weight
    mapping(address => uint256[]) private _gaugeWeightHistory;
    // Last checkpoint for history of gauge vote weight
    mapping(address => DataTypes.Point) private _lastGaugeWeigthCheckpoint;
    // Slope changes for total weight of each gauge
    mapping(address => mapping(uint256 => uint256))
        private _gaugeWeightSlopeChanges;
    // Epoch history of total vote weight
    uint256[] private _totalWeigthHistory;
    // Last checkpoint for the total vote weight
    DataTypes.Point _lastWeightCheckpoint;
    // Slope changes for total weight
    mapping(uint256 => uint256) private _totalWeightSlopeChanges;
    // Weight vote power used by each user (%), smallest tick is 0.01%
    mapping(address => uint256) _userVotePower;
    // Weight vote power each user has in each gauge
    mapping(address => mapping(address => DataTypes.VoteBalance)) _userGaugeVoteBalance;

    mapping(address => address) _reserveToGauge;
    mapping(address => bool) _isGauge;

    function initialize(
        IAddressesProvider addressProvider
    ) external initializer {
        __Ownable_init();
        _addressProvider = addressProvider;
    }

    // Add a gauge (should be done by the admin)
    function addGauge(address reserve, address gauge) external onlyOwner {
        _reserveToGauge[reserve] = gauge;
        _isGauge[gauge] = true;

        emit AddGauge(reserve, gauge);
    }

    // Remove a gauge (should be done by the admin)
    function removeGauge(address reserve, address gauge) external onlyOwner {
        delete _reserveToGauge[reserve];
        delete _isGauge[gauge];

        emit RemoveGauge(reserve, gauge);
    }

    function isGauge(address gauge) external view returns (bool) {
        return _isGauge[gauge];
    }

    function getGauge(address reserve) external view returns (address) {
        return _reserveToGauge[reserve];
    }

    function getGaugeWeight(address gauge) external view returns (uint256) {
        DataTypes.Point
            memory lastWeightCheckpoint = _lastGaugeWeigthCheckpoint[gauge];
        return
            lastWeightCheckpoint.bias -
            lastWeightCheckpoint.slope *
            (block.timestamp - lastWeightCheckpoint.timestamp);
    }

    function getGaugeWeightAt(
        address gauge,
        uint256 epoch
    ) external view returns (uint256) {
        return _gaugeWeightHistory[gauge][epoch];
    }

    function getTotalWeight() external view returns (uint256) {
        return
            _lastWeightCheckpoint.bias -
            _lastWeightCheckpoint.slope *
            (block.timestamp - _lastWeightCheckpoint.timestamp);
    }

    function getTotalWeightAt(uint256 epoch) external view returns (uint256) {
        return _totalWeigthHistory[epoch];
    }

    // Get current used vote power for user
    function voteUserPower(address user) external view returns (uint256) {
        return _userVotePower[user];
    }

    function userGaugeVoteWeight(
        address user,
        address gauge
    ) external view returns (uint256) {
        return _userGaugeVoteBalance[user][gauge].weight;
    }

    function writeTotalWeightHistory() public {
        // Update last saved weight checkpoint and record weight for epochs
        // Will break if is not used for 128 weeks
        uint256 epochTimestampPointer = (_lastWeightCheckpoint.timestamp /
            Time.WEEK) * Time.WEEK;
        for (uint256 i = 0; i < 2 ** 7; i++) {
            //Increase epoch timestamp
            epochTimestampPointer += Time.WEEK;
            if (epochTimestampPointer > block.timestamp) {
                break;
            }

            // Save epoch total weight
            _totalWeigthHistory.push(
                _lastWeightCheckpoint.bias -
                    _lastWeightCheckpoint.slope *
                    (block.timestamp - _lastWeightCheckpoint.timestamp)
            );

            // Update slope
            _lastWeightCheckpoint.slope += _totalWeightSlopeChanges[
                epochTimestampPointer
            ];
        }
    }

    function writeGaugeWeightHistory(address gauge) public {
        // Update last saved weight checkpoint and record weight for epochs
        // Will break if is not used for 128 weeks
        uint256 epochTimestampPointer = (_lastGaugeWeigthCheckpoint[gauge]
            .timestamp / Time.WEEK) * Time.WEEK;
        for (uint256 i = 0; i < 2 ** 7; i++) {
            //Increase epoch timestamp
            epochTimestampPointer += Time.WEEK;
            if (epochTimestampPointer > block.timestamp) {
                break;
            }

            // Save epoch total weight
            _gaugeWeightHistory[gauge].push(
                _lastGaugeWeigthCheckpoint[gauge].bias -
                    _lastWeightCheckpoint.slope *
                    (block.timestamp -
                        _lastGaugeWeigthCheckpoint[gauge].timestamp)
            );

            // Update slope
            _lastGaugeWeigthCheckpoint[gauge].slope += _gaugeWeightSlopeChanges[
                gauge
            ][epochTimestampPointer];
        }
    }

    function vote(address gauge, uint256 weight) external {
        IVotingEscrow votingEscrow = IVotingEscrow(
            _addressProvider.getVotingEscrow()
        );

        // Get user locked balance
        DataTypes.LockedBalance memory userLockedBalance = votingEscrow.locked(
            msg.sender
        );

        require(
            weight > 0 && weight < PercentageMath.PERCENTAGE_FACTOR,
            "Vote weight must belong to [0, 10000]"
        );

        require(
            weight +
                _userVotePower[msg.sender] -
                _userGaugeVoteBalance[gauge][msg.sender].weight <=
                PercentageMath.PERCENTAGE_FACTOR,
            "Vote power over 100%"
        );

        require(
            userLockedBalance.end > block.timestamp,
            "Must have an active vote in order to vote"
        );

        require(
            userLockedBalance.amount > 0,
            "Must have locked balance bigger than 0 to vote"
        );

        // Write weight history to make sure its up to date until this epoch
        writeTotalWeightHistory();
        writeGaugeWeightHistory(gauge);

        // Get user veCRV last action
        DataTypes.Point memory userLastPoint = votingEscrow.getUserHistoryPoint(
            msg.sender,
            votingEscrow.userHistoryLength(msg.sender) - 1
        );

        // If we alredy have votes in this gauge update old slopes
        if (_userGaugeVoteBalance[gauge][msg.sender].weight != 0) {
            _gaugeWeightSlopeChanges[gauge][
                _userGaugeVoteBalance[gauge][msg.sender].end
            ] -= _userGaugeVoteBalance[gauge][msg.sender].slope;

            _totalWeightSlopeChanges[
                _userGaugeVoteBalance[gauge][msg.sender].end
            ] -= _userGaugeVoteBalance[gauge][msg.sender].slope;
        }

        // Add new slope updates
        _gaugeWeightSlopeChanges[gauge][userLockedBalance.end] += userLastPoint
            .slope;
        _totalWeightSlopeChanges[userLockedBalance.end] += userLastPoint.slope;

        // Update checkpoints
        _lastGaugeWeigthCheckpoint[gauge].bias +=
            weight -
            _userGaugeVoteBalance[gauge][msg.sender].weight;
        _lastGaugeWeigthCheckpoint[gauge].slope +=
            userLastPoint.slope -
            _userGaugeVoteBalance[gauge][msg.sender].slope;
        _lastGaugeWeigthCheckpoint[gauge].timestamp = block.timestamp;
        _lastWeightCheckpoint.bias =
            weight -
            _userGaugeVoteBalance[gauge][msg.sender].weight;
        _lastWeightCheckpoint.slope +=
            userLastPoint.slope -
            _userGaugeVoteBalance[gauge][msg.sender].slope;
        _lastWeightCheckpoint.timestamp = block.timestamp;

        // Change used vote power
        _userVotePower[msg.sender] =
            weight +
            _userVotePower[msg.sender] -
            _userGaugeVoteBalance[gauge][msg.sender].weight;

        // Update user gauge vote info
        _userGaugeVoteBalance[gauge][msg.sender] = DataTypes.VoteBalance(
            weight,
            userLastPoint.slope,
            userLockedBalance.end
        );

        emit Vote(msg.sender, gauge, weight);
    }
}
