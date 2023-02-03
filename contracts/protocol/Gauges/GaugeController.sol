//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;

import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {PercentageMath} from "../../libraries/math/PercentageMath.sol";
import {DataTypes} from "../../libraries/types/DataTypes.sol";
import {IVotingEscrow} from "../../interfaces/IVotingEscrow.sol";
import {IGaugeController} from "../../interfaces/IGaugeController.sol";
import {IAddressesProvider} from "../../interfaces/IAddressesProvider.sol";
import {IGauge} from "../../interfaces/IGauge.sol";
import {INativeToken} from "../../interfaces/INativeToken.sol";
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
    // Uset vote ratio used by each user (%), smallest tick is 0.01%
    mapping(address => uint256) _userVoteRatio;
    // User vote ratio used by each user at each gauge (%), smallest tick is 0.01%
    mapping(address => mapping(address => uint256)) _userGaugeVoteRatio;
    // Weight vote power each user has in each gauge
    mapping(address => mapping(address => DataTypes.Point)) _userGaugeVoteWeight;
    mapping(address => bool) _isGauge;
    mapping(address => address) _liquidityPoolToGauge;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

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
    ) public returns (uint256) {
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

    function getTotalWeightAt(uint256 epoch) public returns (uint256) {
        // Update total weight history
        writeTotalWeightHistory();

        return _totalWeigthHistory[epoch];
    }

    // Get current used vote power for user
    function userVoteRatio(address user) external view returns (uint256) {
        return _userVoteRatio[user];
    }

    function userVoteRatioForGauge(
        address user,
        address gauge
    ) external view returns (uint256) {
        require(_isGauge[gauge], "Gauge is not on the gauge list");

        return _userGaugeVoteRatio[user][gauge];
    }

    function userVoteWeightForGauge(
        address user,
        address gauge
    ) external view returns (uint256) {
        require(_isGauge[gauge], "Gauge is not on the gauge list");

        if (
            _userGaugeVoteWeight[user][gauge].slope *
                (block.timestamp -
                    _userGaugeVoteWeight[user][gauge].timestamp) >
            _userGaugeVoteWeight[user][gauge].bias
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
            _lastWeightCheckpoint.slope -= _totalWeightSlopeChanges[
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
            _lastGaugeWeigthCheckpoint[gauge].slope -= _gaugeWeightSlopeChanges[
                gauge
            ][epochTimestampPointer];

            epochTimestampPointer += Time.WEEK;
        }
    }

    // Vote for a gauge, ratio is % of user ve weighted balance
    function vote(address gauge, uint256 ratio) external {
        IVotingEscrow votingEscrow = IVotingEscrow(
            _addressProvider.getVotingEscrow()
        );

        // Get user locked balance
        DataTypes.LockedBalance memory userLockedBalance = votingEscrow.locked(
            msg.sender
        );

        require(ratio > 0, "Vote ratio must be higher than 0");

        require(
            ratio +
                _userVoteRatio[msg.sender] -
                _userGaugeVoteRatio[msg.sender][gauge] <=
                PercentageMath.PERCENTAGE_FACTOR, // 100%
            "Total vote ratio must be smaller than 100%"
        );

        require(
            userLockedBalance.end > block.timestamp || ratio == 0,
            "Must have an active lock in order to vote"
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
        DataTypes.Point memory oldGaugeVoteWeight;
        uint256 voteWeight = (userLastPoint.bias * ratio) /
            PercentageMath.PERCENTAGE_FACTOR;
        uint256 voteSlope = (userLastPoint.slope * ratio) /
            PercentageMath.PERCENTAGE_FACTOR;

        // If we alredy have valid votes in this gauge
        if (
            _userGaugeVoteRatio[msg.sender][gauge] != 0 &&
            block.timestamp < userLockedBalance.end
        ) {
            _gaugeWeightSlopeChanges[gauge][
                userLockedBalance.end
            ] -= _userGaugeVoteWeight[msg.sender][gauge].slope;

            _totalWeightSlopeChanges[
                userLockedBalance.end
            ] -= _userGaugeVoteWeight[msg.sender][gauge].slope;

            oldGaugeVoteWeight = _userGaugeVoteWeight[msg.sender][gauge];
        }

        // Add new slope updates
        _gaugeWeightSlopeChanges[gauge][userLockedBalance.end] += voteSlope;
        _totalWeightSlopeChanges[userLockedBalance.end] += voteSlope;

        // Update checkpoints
        _lastGaugeWeigthCheckpoint[gauge].bias +=
            voteWeight -
            oldGaugeVoteWeight.bias;
        _lastGaugeWeigthCheckpoint[gauge].slope +=
            userLastPoint.slope -
            oldGaugeVoteWeight.slope;
        _lastGaugeWeigthCheckpoint[gauge].timestamp = block.timestamp;
        _lastWeightCheckpoint.bias = voteWeight - oldGaugeVoteWeight.bias;
        _lastWeightCheckpoint.slope +=
            userLastPoint.slope -
            oldGaugeVoteWeight.slope;
        _lastWeightCheckpoint.timestamp = block.timestamp;

        // Update user vote info
        _userVoteRatio[msg.sender] =
            ratio +
            _userVoteRatio[msg.sender] -
            _userGaugeVoteRatio[msg.sender][gauge];
        _userGaugeVoteRatio[msg.sender][gauge] = ratio;

        _userGaugeVoteWeight[msg.sender][gauge] = DataTypes.Point(
            voteWeight,
            voteSlope,
            userLastPoint.timestamp
        );

        emit Vote(msg.sender, gauge, ratio);
    }

    function getGaugeRewards(
        address gauge,
        uint256 epoch
    ) external returns (uint256 rewards) {
        require(_isGauge[gauge], "Gauge is not on the gauge list");

        console.log(
            "getEpochRewards",
            INativeToken(_addressProvider.getNativeToken()).getEpochRewards(
                epoch
            )
        );

        console.log("getTotalWeightAt", getTotalWeightAt(epoch));

        if (getTotalWeightAt(epoch) == 0) {
            return 0;
        }

        return
            (INativeToken(_addressProvider.getNativeToken()).getEpochRewards(
                epoch
            ) * getGaugeWeightAt(gauge, epoch)) / getTotalWeightAt(epoch);
    }
}
