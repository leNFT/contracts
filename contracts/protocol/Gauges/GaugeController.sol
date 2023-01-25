//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;

import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {PercentageMath} from "../../libraries/math/PercentageMath.sol";
import {DataTypes} from "../../libraries/types/DataTypes.sol";
import {IVotingEscrow} from "../../interfaces/IVotingEscrow.sol";
import {IGaugeController} from "../../interfaces/IGaugeController.sol";
import {IAddressesProvider} from "../../interfaces/IAddressesProvider.sol";
import {IGauge} from "../../interfaces/IGauge.sol";
import "hardhat/console.sol";
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
    mapping(address => DataTypes.Point) _userVoteWeight;
    // Weight vote power each user has in each gauge
    mapping(address => mapping(address => DataTypes.Point)) _userGaugeVoteWeight;
    mapping(address => bool) _isGauge;
    mapping(address => address) _liquidityPoolToGauge;

    function initialize(
        IAddressesProvider addressProvider
    ) external initializer {
        __Ownable_init();
        _addressProvider = addressProvider;
        _totalWeigthHistory.push(0);
        _lastWeightCheckpoint = DataTypes.Point(0, 0, block.timestamp);
    }

    // Add a gauge (should be done by the admin)
    function addGauge(address gauge) external onlyOwner {
        address liquidityPool = IGauge(gauge).lpToken();
        _liquidityPoolToGauge[liquidityPool] = gauge;
        _isGauge[gauge] = true;

        emit AddGauge(gauge, liquidityPool);
    }

    // Remove a gauge (should be done by the admin)
    function removeGauge(address gauge) external onlyOwner {
        require(_isGauge[gauge], "Gauge is not on the gauge list");

        address liquidityPool = IGauge(gauge).lpToken();
        delete _liquidityPoolToGauge[liquidityPool];
        delete _isGauge[gauge];

        emit RemoveGauge(gauge, liquidityPool);
    }

    function isGauge(address gauge) external view override returns (bool) {
        return _isGauge[gauge];
    }

    function getGauge(address liquidityPool) external view returns (address) {
        return _liquidityPoolToGauge[liquidityPool];
    }

    function getGaugeWeight(address gauge) external view returns (uint256) {
        require(_isGauge[gauge], "Gauge is not on the gauge list");

        DataTypes.Point
            memory lastGaugeWeightCheckpoint = _lastGaugeWeigthCheckpoint[
                gauge
            ];

        if (
            lastGaugeWeightCheckpoint.bias <
            lastGaugeWeightCheckpoint.slope *
                (block.timestamp - lastGaugeWeightCheckpoint.timestamp)
        ) {
            return 0;
        }

        return
            lastGaugeWeightCheckpoint.bias -
            lastGaugeWeightCheckpoint.slope *
            (block.timestamp - lastGaugeWeightCheckpoint.timestamp);
    }

    function getGaugeWeightAt(
        address gauge,
        uint256 epoch
    ) external returns (uint256) {
        require(_isGauge[gauge], "Gauge is not on the gauge list");
        // Update gauge weight history
        writeGaugeWeightHistory(gauge);

        return _gaugeWeightHistory[gauge][epoch];
    }

    function getTotalWeight() external view returns (uint256) {
        if (
            _lastWeightCheckpoint.bias <
            _lastWeightCheckpoint.slope *
                (block.timestamp - _lastWeightCheckpoint.timestamp)
        ) {
            return 0;
        }

        return
            _lastWeightCheckpoint.bias -
            _lastWeightCheckpoint.slope *
            (block.timestamp - _lastWeightCheckpoint.timestamp);
    }

    function getTotalWeightAt(uint256 epoch) external returns (uint256) {
        // Update total weight history
        writeTotalWeightHistory();

        return _totalWeigthHistory[epoch];
    }

    // Get current used vote power for user
    function userVoteWeight(address user) public view returns (uint256) {
        if (
            block.timestamp >
            IVotingEscrow(_addressProvider.getVotingEscrow())
                .locked(msg.sender)
                .end
        ) {
            return 0;
        }

        return
            _userVoteWeight[user].bias -
            _userVoteWeight[user].slope *
            (block.timestamp - _userVoteWeight[user].timestamp);
    }

    function userVoteWeightForGauge(
        address user,
        address gauge
    ) public view returns (uint256) {
        require(_isGauge[gauge], "Gauge is not on the gauge list");

        if (
            block.timestamp >
            IVotingEscrow(_addressProvider.getVotingEscrow())
                .locked(msg.sender)
                .end
        ) {
            return 0;
        }

        return
            _userGaugeVoteWeight[user][gauge].bias -
            _userGaugeVoteWeight[user][gauge].slope *
            (block.timestamp - _userGaugeVoteWeight[user][gauge].timestamp);
    }

    function writeTotalWeightHistory() public {
        // Update last saved weight checkpoint and record weight for epochs
        // Will break if is not used for 128 weeks
        uint256 epochTimestampPointer = IVotingEscrow(
            _addressProvider.getVotingEscrow()
        ).epochTimestamp(_totalWeigthHistory.length);
        for (uint256 i = 0; i < 2 ** 7; i++) {
            if (epochTimestampPointer > block.timestamp) {
                break;
            }

            // Save epoch total weight
            uint256 epochTotalWeight = _lastWeightCheckpoint.bias -
                _lastWeightCheckpoint.slope *
                (epochTimestampPointer - _lastWeightCheckpoint.timestamp);
            _totalWeigthHistory.push(epochTotalWeight);

            // Update last weight checkpoint
            _lastWeightCheckpoint.bias = epochTotalWeight;
            _lastWeightCheckpoint.timestamp = epochTimestampPointer;
            _lastWeightCheckpoint.slope += _totalWeightSlopeChanges[
                epochTimestampPointer
            ];
        }

        //Increase epoch timestamp
        epochTimestampPointer += Time.WEEK;
    }

    function writeGaugeWeightHistory(address gauge) public {
        require(_isGauge[gauge], "Gauge is not on the gauge list");

        // If the gauge weights are empty set the weight for the first epoch
        if (_gaugeWeightHistory[gauge].length == 0) {
            _gaugeWeightHistory[gauge].push(0);
            _lastGaugeWeigthCheckpoint[gauge] = DataTypes.Point(
                0,
                0,
                IVotingEscrow(_addressProvider.getVotingEscrow())
                    .epochTimestamp(0)
            );
        }

        // Update last saved weight checkpoint and record weight for epochs
        // Will break if is not used for 128 weeks
        uint256 epochTimestampPointer = IVotingEscrow(
            _addressProvider.getVotingEscrow()
        ).epochTimestamp(_gaugeWeightHistory[gauge].length);
        for (uint256 i = 0; i < 2 ** 7; i++) {
            //Increase epoch timestamp
            if (epochTimestampPointer > block.timestamp) {
                break;
            }

            // Save epoch total weight
            uint256 epochGaugeWeight = _lastGaugeWeigthCheckpoint[gauge].bias -
                _lastWeightCheckpoint.slope *
                (epochTimestampPointer -
                    _lastGaugeWeigthCheckpoint[gauge].timestamp);
            _gaugeWeightHistory[gauge].push(epochGaugeWeight);

            // Update last weight checkpoint
            _lastGaugeWeigthCheckpoint[gauge].bias = epochGaugeWeight;
            _lastGaugeWeigthCheckpoint[gauge].timestamp = epochTimestampPointer;
            _lastGaugeWeigthCheckpoint[gauge].slope += _gaugeWeightSlopeChanges[
                gauge
            ][epochTimestampPointer];

            epochTimestampPointer += Time.WEEK;
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

        require(weight > 0, "Vote weight must be higher than 0");

        require(
            weight + userVoteWeight(msg.sender) <=
                votingEscrow.balanceOf(msg.sender),
            "Total vote weight must be smaller than locked weight"
        );

        require(
            userLockedBalance.end > block.timestamp,
            "Must have an active vote in order to vote"
        );

        require(
            userLockedBalance.amount > 0,
            "Must have locked balance bigger than 0 to vote"
        );

        require(_isGauge[gauge], "Gauge is not on the gauge list");

        // Write weight history to make sure its up to date until this epoch
        writeTotalWeightHistory();
        writeGaugeWeightHistory(gauge);

        // Get user  last action
        DataTypes.Point memory userLastPoint = votingEscrow.getUserHistoryPoint(
            msg.sender,
            votingEscrow.userHistoryLength(msg.sender) - 1
        );

        // If we alredy have votes in this gauge update old slopes
        if (
            userVoteWeightForGauge(msg.sender, gauge) != 0 &&
            block.timestamp < userLockedBalance.end
        ) {
            _gaugeWeightSlopeChanges[gauge][
                userLockedBalance.end
            ] -= _userGaugeVoteWeight[msg.sender][gauge].slope;

            _totalWeightSlopeChanges[
                userLockedBalance.end
            ] -= _userGaugeVoteWeight[msg.sender][gauge].slope;
        }

        // Add new slope updates
        _gaugeWeightSlopeChanges[gauge][userLockedBalance.end] += userLastPoint
            .slope;
        _totalWeightSlopeChanges[userLockedBalance.end] += userLastPoint.slope;

        // Update checkpoints
        _lastGaugeWeigthCheckpoint[gauge].bias +=
            weight -
            _userGaugeVoteWeight[msg.sender][gauge].bias;
        _lastGaugeWeigthCheckpoint[gauge].slope +=
            userLastPoint.slope -
            _userGaugeVoteWeight[msg.sender][gauge].slope;
        _lastGaugeWeigthCheckpoint[gauge].timestamp = block.timestamp;
        _lastWeightCheckpoint.bias =
            weight -
            _userGaugeVoteWeight[msg.sender][gauge].bias;
        _lastWeightCheckpoint.slope +=
            userLastPoint.slope -
            _userGaugeVoteWeight[msg.sender][gauge].slope;
        _lastWeightCheckpoint.timestamp = block.timestamp;

        // Update user gauge vote info
        _userGaugeVoteWeight[msg.sender][gauge] = DataTypes.Point(
            weight,
            userLastPoint.slope,
            userLastPoint.timestamp
        );

        emit Vote(msg.sender, gauge, weight);
    }
}
