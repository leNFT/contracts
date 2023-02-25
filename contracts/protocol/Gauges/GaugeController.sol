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

/// @title Gauge Controller
/// @dev Contract that manages gauge vote weights, total vote weight, user vote power in each gauge, and user vote ratios.
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

    /// @notice Initializes the contract by setting up the owner and the addresses provider contract.
    /// @param addressProvider Address provider contract.
    function initialize(
        IAddressesProvider addressProvider
    ) external initializer {
        __Ownable_init();
        _addressProvider = addressProvider;
        _totalWeigthHistory.push(0);
        _lastWeightCheckpoint = DataTypes.Point(0, 0, block.timestamp);
    }

    /// @notice Adds a gauge contract to the list of registered gauges.
    /// @dev Only the contract owner can call this method.
    /// @param gauge Address of the gauge contract to add.
    function addGauge(address gauge) external onlyOwner {
        address liquidityPool = IGauge(gauge).lpToken();
        _liquidityPoolToGauge[liquidityPool] = gauge;
        _isGauge[gauge] = true;

        emit AddGauge(gauge, liquidityPool);
    }

    /// @notice Remove a gauge
    /// @dev Only the contract owner can call this method.
    /// @param gauge The address of the gauge to be removed
    function removeGauge(address gauge) external onlyOwner {
        require(_isGauge[gauge], "Gauge is not on the gauge list");

        address liquidityPool = IGauge(gauge).lpToken();
        delete _liquidityPoolToGauge[liquidityPool];
        delete _isGauge[gauge];

        emit RemoveGauge(gauge, liquidityPool);
    }

    /// @notice Check if a gauge exists
    /// @param gauge The address of the gauge to check
    /// @return A boolean indicating whether the gauge exists
    function isGauge(address gauge) external view override returns (bool) {
        return _isGauge[gauge];
    }

    /// @notice Get the gauge associated with a given liquidity pool
    /// @param liquidityPool The address of the liquidity pool to check
    /// @return The address of the gauge associated with the liquidity pool
    function getGauge(address liquidityPool) external view returns (address) {
        return _liquidityPoolToGauge[liquidityPool];
    }

    /// @notice Get the current weight of a gauge
    /// @param gauge The address of the gauge to check
    /// @return The current weight of the gauge
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

    /// @notice Get the weight of a gauge at a specific epoch
    /// @param gauge The address of the gauge to check
    /// @param epoch The epoch for which to retrieve the gauge weight
    /// @return The weight of the gauge at the specified epoch
    function getGaugeWeightAt(
        address gauge,
        uint256 epoch
    ) public returns (uint256) {
        require(_isGauge[gauge], "Gauge is not on the gauge list");
        // Update gauge weight history
        writeGaugeWeightHistory(gauge);

        return _gaugeWeightHistory[gauge][epoch];
    }

    /// @notice Get the total weight sum of all gauges
    /// @return The total weight sum of all gauges
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

    /// @notice Get the total weight of all gauges at a specific epoch
    /// @param epoch The epoch for which to retrieve the total weight
    /// @return The total weight of all gauges at the specified epoch
    function getTotalWeightAt(uint256 epoch) public returns (uint256) {
        // Update total weight history
        writeTotalWeightHistory();

        return _totalWeigthHistory[epoch];
    }

    /// @notice Get the current used vote power for a given user.
    /// @param user The address of the user.
    /// @return The current used vote power.
    function userVoteRatio(address user) external view returns (uint256) {
        return _userVoteRatio[user];
    }

    /// @notice  Get the current used vote power for a given user in a specific gauge.
    /// @param user The address of the user.
    /// @param gauge The address of the gauge.
    /// @return The current used vote power for the given user in the specified gauge.
    function userVoteRatioForGauge(
        address user,
        address gauge
    ) external view returns (uint256) {
        require(_isGauge[gauge], "Gauge is not on the gauge list");

        return _userGaugeVoteRatio[user][gauge];
    }

    /// @notice Get the vote weight for a user in a specific gauge.
    ///@param user The address of the user.
    /// @param gauge The address of the gauge.
    /// @return The vote weight for the user in the specified gauge.
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

    /// @notice Update the total weight history
    function writeTotalWeightHistory() public {
        // Update last saved weight checkpoint and record weight for epochs
        // Will break if is not used for 128 epochs
        IVotingEscrow votingEscrow = IVotingEscrow(
            _addressProvider.getVotingEscrow()
        );
        uint256 epochTimestampPointer = votingEscrow.epochTimestamp(
            _totalWeigthHistory.length
        );
        uint256 epochPeriod = votingEscrow.epochPeriod();

        for (uint256 i = 0; i < 2 ** 7; i++) {
            if (epochTimestampPointer > block.timestamp) {
                break;
            }

            // Save epoch total weight
            uint256 epochTotalWeight = _lastWeightCheckpoint.bias -
                (_lastWeightCheckpoint.slope *
                    (epochTimestampPointer - _lastWeightCheckpoint.timestamp));
            _totalWeigthHistory.push(epochTotalWeight);

            // Update last weight checkpoint
            _lastWeightCheckpoint.bias = epochTotalWeight;
            _lastWeightCheckpoint.timestamp = epochTimestampPointer;
            _lastWeightCheckpoint.slope -= _totalWeightSlopeChanges[
                epochTimestampPointer
            ];

            //Increase epoch timestamp
            epochTimestampPointer += epochPeriod;
        }
    }

    /// @notice Update the weight history of a gauge
    /// @param gauge The address of the gauge to update
    function writeGaugeWeightHistory(address gauge) public {
        require(_isGauge[gauge], "Gauge is not on the gauge list");

        IVotingEscrow votingEscrow = IVotingEscrow(
            _addressProvider.getVotingEscrow()
        );

        // If the gauge weights are empty set the weight for the first epoch
        if (_gaugeWeightHistory[gauge].length == 0) {
            _gaugeWeightHistory[gauge].push(0);
            _lastGaugeWeigthCheckpoint[gauge] = DataTypes.Point(
                0,
                0,
                votingEscrow.epochTimestamp(0)
            );
        }

        // Update last saved weight checkpoint and record weight for epochs
        // Will break if is not used for 128 epochs
        uint256 epochPeriod = votingEscrow.epochPeriod();
        uint256 epochTimestampPointer = votingEscrow.epochTimestamp(
            _gaugeWeightHistory[gauge].length
        );

        for (uint256 i = 0; i < 2 ** 7; i++) {
            //Increase epoch timestamp
            if (epochTimestampPointer > block.timestamp) {
                break;
            }
            // Save epoch total weight
            uint256 epochGaugeWeight = _lastGaugeWeigthCheckpoint[gauge].bias -
                _lastGaugeWeigthCheckpoint[gauge].slope *
                (epochTimestampPointer -
                    _lastGaugeWeigthCheckpoint[gauge].timestamp);
            _gaugeWeightHistory[gauge].push(epochGaugeWeight);

            // Update last weight checkpoint
            _lastGaugeWeigthCheckpoint[gauge].bias = epochGaugeWeight;
            _lastGaugeWeigthCheckpoint[gauge].timestamp = epochTimestampPointer;
            _lastGaugeWeigthCheckpoint[gauge].slope -= _gaugeWeightSlopeChanges[
                gauge
            ][epochTimestampPointer];

            epochTimestampPointer += epochPeriod;
        }
    }

    /// @notice Vote for a gauge
    /// @param gauge The address of the gauge to vote for
    /// @param ratio The ratio of the vote power to use
    function vote(address gauge, uint256 ratio) external {
        IVotingEscrow votingEscrow = IVotingEscrow(
            _addressProvider.getVotingEscrow()
        );

        // Get user locked balance
        DataTypes.LockedBalance memory userLockedBalance = votingEscrow.locked(
            msg.sender
        );

        require(
            ratio +
                _userVoteRatio[msg.sender] -
                _userGaugeVoteRatio[msg.sender][gauge] <=
                PercentageMath.PERCENTAGE_FACTOR, // 100%
            "Total vote ratio must be smaller than 100%"
        );

        require(
            userLockedBalance.end > block.timestamp || ratio == 0,
            "Must have an active lock in order to vote unless it's erasing a vote"
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
        DataTypes.Point memory newGaugeVoteWeight;

        // Get the updated ne w gauge vote weight
        newGaugeVoteWeight.bias =
            ((userLastPoint.bias -
                (userLastPoint.slope *
                    (block.timestamp - userLastPoint.timestamp))) * ratio) /
            PercentageMath.PERCENTAGE_FACTOR;
        newGaugeVoteWeight.slope =
            (userLastPoint.slope * ratio) /
            PercentageMath.PERCENTAGE_FACTOR;
        newGaugeVoteWeight.timestamp = block.timestamp;

        // If we already have valid votes in this gauge
        if (
            _userGaugeVoteRatio[msg.sender][gauge] > 0 &&
            block.timestamp < userLockedBalance.end
        ) {
            // Get the updated old gauge vote weight
            oldGaugeVoteWeight.bias =
                _userGaugeVoteWeight[msg.sender][gauge].slope *
                (block.timestamp -
                    _userGaugeVoteWeight[msg.sender][gauge].timestamp);
            oldGaugeVoteWeight.slope = _userGaugeVoteWeight[msg.sender][gauge]
                .slope;
            oldGaugeVoteWeight.timestamp = block.timestamp;

            _gaugeWeightSlopeChanges[gauge][
                userLockedBalance.end
            ] -= oldGaugeVoteWeight.slope;

            _totalWeightSlopeChanges[
                userLockedBalance.end
            ] -= oldGaugeVoteWeight.slope;
        }

        // Add new slope updates
        _gaugeWeightSlopeChanges[gauge][
            userLockedBalance.end
        ] += newGaugeVoteWeight.slope;
        _totalWeightSlopeChanges[userLockedBalance.end] += newGaugeVoteWeight
            .slope;

        // Update checkpoints
        _lastGaugeWeigthCheckpoint[gauge].bias =
            _lastGaugeWeigthCheckpoint[gauge].bias -
            _lastGaugeWeigthCheckpoint[gauge].slope *
            (block.timestamp - _lastGaugeWeigthCheckpoint[gauge].timestamp) +
            newGaugeVoteWeight.bias -
            oldGaugeVoteWeight.bias;
        _lastGaugeWeigthCheckpoint[gauge].slope =
            _lastGaugeWeigthCheckpoint[gauge].slope +
            newGaugeVoteWeight.slope -
            oldGaugeVoteWeight.slope;
        _lastGaugeWeigthCheckpoint[gauge].timestamp = block.timestamp;

        _lastWeightCheckpoint.bias =
            _lastWeightCheckpoint.bias -
            _lastWeightCheckpoint.slope *
            (block.timestamp - _lastWeightCheckpoint.timestamp) +
            newGaugeVoteWeight.bias -
            oldGaugeVoteWeight.bias;
        _lastWeightCheckpoint.slope =
            _lastWeightCheckpoint.slope +
            newGaugeVoteWeight.slope -
            oldGaugeVoteWeight.slope;
        _lastWeightCheckpoint.timestamp = block.timestamp;

        // Update user vote info
        _userVoteRatio[msg.sender] =
            ratio +
            _userVoteRatio[msg.sender] -
            _userGaugeVoteRatio[msg.sender][gauge];
        _userGaugeVoteRatio[msg.sender][gauge] = ratio;
        _userGaugeVoteWeight[msg.sender][gauge] = newGaugeVoteWeight;

        emit Vote(msg.sender, gauge, ratio);
    }

    /// @notice Get the LE reward for a gauge in a given epoch
    /// @param gauge The address of the gauge
    /// @param epoch The epoch to get the reward for
    /// @return rewards The LE reward for the gauge in the given epoch
    function getGaugeRewards(
        address gauge,
        uint256 epoch
    ) external returns (uint256 rewards) {
        require(_isGauge[gauge], "Gauge is not on the gauge list");

        if (getTotalWeightAt(epoch) == 0) {
            return 0;
        }

        return
            (INativeToken(_addressProvider.getNativeToken()).getEpochRewards(
                epoch
            ) * getGaugeWeightAt(gauge, epoch)) / getTotalWeightAt(epoch);
    }
}
