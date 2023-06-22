//SPDX-License-Identifier: Unlicense
pragma solidity 0.8.19;

import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {PercentageMath} from "../../libraries/utils/PercentageMath.sol";
import {DataTypes} from "../../libraries/types/DataTypes.sol";
import {IVotingEscrow} from "../../interfaces/IVotingEscrow.sol";
import {IERC721Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC721/IERC721Upgradeable.sol";
import {IGaugeController} from "../../interfaces/IGaugeController.sol";
import {IAddressProvider} from "../../interfaces/IAddressProvider.sol";
import {ERC165CheckerUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/introspection/ERC165CheckerUpgradeable.sol";
import {IGauge} from "../../interfaces/IGauge.sol";

/// @title Gauge Controller
/// @author leNFT
/// @notice Manages the different gauges
/// @dev Contract that manages gauge vote weights, total vote weight, user vote power in each gauge, and user vote ratios.
contract GaugeController is OwnableUpgradeable, IGaugeController {
    uint256 private constant INFLATION_PERIOD = 52; // 52 epochs (1 year)
    uint256 private constant MAX_INFLATION_PERIODS = 8; // Maximum 8 inflation periods (8 years) and then base emissions
    uint256 private constant LOADING_PERIOD = 24; // 24 epochs (6 months)
    uint256 private constant INITIAL_REWARDS = 28e23; // 2.8 million tokens per epoch

    IAddressProvider private immutable _addressProvider;

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
    DataTypes.Point private _lastWeightCheckpoint;
    // Slope changes for total weight
    mapping(uint256 => uint256) private _totalWeightSlopeChanges;
    // vote ratio being used by each lock (%), smallest tick is 0.01%
    mapping(uint256 => uint256) private _lockVoteRatio;
    // User vote ratio used by each lock at each gauge (%), smallest tick is 0.01%
    mapping(uint256 => mapping(address => uint256)) private _lockGaugeVoteRatio;
    // Weight vote power each lock has in each gauge
    mapping(uint256 => mapping(address => DataTypes.Point))
        private _lockGaugeVotePoint;
    mapping(address => bool) private _isGauge;
    mapping(address => address) private _liquidityPoolToGauge;
    uint256 private _lpMaturityPeriod; // in seconds

    using ERC165CheckerUpgradeable for address;

    modifier validGauge(address gauge) {
        _requireValidGauge(gauge);
        _;
    }

    modifier noFutureEpoch(uint256 epoch) {
        _requireNoFutureEpoch(epoch);
        _;
    }

    modifier lockExists(uint256 lockId) {
        _requireLockExists(lockId);
        _;
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor(IAddressProvider addressProvider) {
        _addressProvider = addressProvider;
        _disableInitializers();
    }

    /// @notice Initializes the contract by setting up the owner and the addresses provider contract.
    /// @param lpMaturityPeriod The maturity period for the LP tokens
    function initialize(uint256 lpMaturityPeriod) external initializer {
        __Ownable_init();
        _lpMaturityPeriod = lpMaturityPeriod;
        _totalWeigthHistory.push(0);
        _lastWeightCheckpoint = DataTypes.Point(0, 0, block.timestamp);
    }

    /// @notice Adds a gauge contract to the list of registered gauges.
    /// @dev Only the contract owner can call this method.
    /// @param gauge Address of the gauge contract to add.
    function addGauge(address gauge) external onlyOwner {
        // Check if the gauge is already registered
        require(!_isGauge[gauge], "GC:AG:GAUGE_ALREADY_ADDED");

        // Check if the gauge is a valid gauge
        require(
            gauge.supportsInterface(type(IGauge).interfaceId),
            "GC:AG:INVALID_GAUGE"
        );

        address liquidityPool = IGauge(gauge).getLPToken();
        _liquidityPoolToGauge[liquidityPool] = gauge;
        _isGauge[gauge] = true;

        emit AddGauge(gauge, liquidityPool);
    }

    /// @notice Remove a gauge
    /// @dev Only the contract owner can call this method.
    /// @param gauge The address of the gauge to be removed
    function removeGauge(address gauge) external onlyOwner validGauge(gauge) {
        address liquidityPool = IGauge(gauge).getLPToken();
        if (_liquidityPoolToGauge[liquidityPool] == gauge) {
            delete _liquidityPoolToGauge[liquidityPool];
        }

        delete _isGauge[gauge];

        emit RemoveGauge(gauge, liquidityPool);
    }

    /// @notice Check if a gauge exists (meaning is registered with the gauge controller)
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
    function getGaugeWeight(
        address gauge
    ) external view validGauge(gauge) returns (uint256) {
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
    ) public noFutureEpoch(epoch) validGauge(gauge) returns (uint256) {
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
    function getTotalWeightAt(
        uint256 epoch
    ) public noFutureEpoch(epoch) returns (uint256) {
        // Update total weight history
        writeTotalWeightHistory();

        return _totalWeigthHistory[epoch];
    }

    /// @notice Get the current used vote power for a given lock.
    /// @param tokenId The tokenId of the lock.
    /// @return The current used vote power.
    function getLockVoteRatio(
        uint256 tokenId
    ) external view override lockExists(tokenId) returns (uint256) {
        return _lockVoteRatio[tokenId];
    }

    /// @notice  Get the current used vote power for a given user in a specific gauge.
    /// @param tokenId The tokenId of the lock.
    /// @param gauge The address of the gauge.
    /// @return The current used vote power for the given user in the specified gauge.
    function getLockVoteRatioForGauge(
        uint256 tokenId,
        address gauge
    ) external view validGauge(gauge) lockExists(tokenId) returns (uint256) {
        return _lockGaugeVoteRatio[tokenId][gauge];
    }

    /// @notice Get the vote point for a lock in a specific gauge.
    /// @param tokenId The tokenId of the lock.
    /// @param gauge The address of the gauge.
    function getLockVotePointForGauge(
        uint256 tokenId,
        address gauge
    )
        external
        view
        validGauge(gauge)
        lockExists(tokenId)
        returns (DataTypes.Point memory)
    {
        return _lockGaugeVotePoint[tokenId][gauge];
    }

    /// @notice Get the vote weight for a user in a specific gauge.
    /// @param tokenId The tokenId of the lock.
    /// @param gauge The address of the gauge.
    /// @return The vote weight for the user in the specified gauge.
    function getLockVoteWeightForGauge(
        uint256 tokenId,
        address gauge
    ) external view validGauge(gauge) lockExists(tokenId) returns (uint256) {
        if (
            _lockGaugeVotePoint[tokenId][gauge].slope *
                (block.timestamp -
                    _lockGaugeVotePoint[tokenId][gauge].timestamp) >
            _lockGaugeVotePoint[tokenId][gauge].bias
        ) {
            return 0;
        }

        return
            _lockGaugeVotePoint[tokenId][gauge].bias -
            _lockGaugeVotePoint[tokenId][gauge].slope *
            (block.timestamp - _lockGaugeVotePoint[tokenId][gauge].timestamp);
    }

    /// @notice Update the total weight history
    function writeTotalWeightHistory() public {
        // Update last saved weight checkpoint and record weight for epochs
        // Will break if is not used for 128 epochs
        IVotingEscrow votingEscrow = IVotingEscrow(
            _addressProvider.getVotingEscrow()
        );
        uint256 epochTimestampPointer = votingEscrow.getEpochTimestamp(
            _totalWeigthHistory.length
        );
        uint256 epochPeriod = votingEscrow.getEpochPeriod();

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
    function writeGaugeWeightHistory(address gauge) public validGauge(gauge) {
        IVotingEscrow votingEscrow = IVotingEscrow(
            _addressProvider.getVotingEscrow()
        );

        // If the gauge weights are empty set the weight for the first epoch
        if (_gaugeWeightHistory[gauge].length == 0) {
            _gaugeWeightHistory[gauge].push(0);
            _lastGaugeWeigthCheckpoint[gauge] = DataTypes.Point(
                0,
                0,
                votingEscrow.getEpochTimestamp(0)
            );
        }

        // Update last saved weight checkpoint and record weight for epochs
        // Will break if is not used for 128 epochs
        uint256 epochPeriod = votingEscrow.getEpochPeriod();
        uint256 epochTimestampPointer = votingEscrow.getEpochTimestamp(
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
    /// @param tokenId The tokenId of the lock.
    /// @param gauge The address of the gauge to vote for
    /// @param ratio The ratio of the vote power to use
    function vote(
        uint256 tokenId,
        address gauge,
        uint256 ratio
    ) external lockExists(tokenId) validGauge(gauge) {
        //Must be the owner of the lock to use it to vote
        IVotingEscrow votingEscrow = IVotingEscrow(
            _addressProvider.getVotingEscrow()
        );
        require(
            IERC721Upgradeable(address(votingEscrow)).ownerOf(tokenId) ==
                msg.sender,
            "GC:V:NOT_LOCK_OWNER"
        );

        // Get user locked balance
        DataTypes.LockedBalance memory lockedBalance = votingEscrow.getLock(
            tokenId
        );

        require(
            ratio +
                _lockVoteRatio[tokenId] -
                _lockGaugeVoteRatio[tokenId][gauge] <=
                PercentageMath.PERCENTAGE_FACTOR, // 100%
            "GC:V:INVALID_RATIO"
        );

        // Lock must not be expired unless the ratio is 0 (we are removing the vote)
        require(
            lockedBalance.end > block.timestamp || ratio == 0,
            "GC:V:LOCK_EXPIRED"
        );

        require(lockedBalance.amount > 0, "GC:V:LOCKED_BALANCE_ZERO");

        require(_isGauge[gauge], "GC:V:INVALID_GAUGE");

        // Write weight history to make sure its up to date until this epoch
        writeTotalWeightHistory();
        writeGaugeWeightHistory(gauge);

        // Get lock last action
        DataTypes.Point memory lockLastPoint = votingEscrow.getLockHistoryPoint(
            tokenId,
            votingEscrow.getLockHistoryLength(tokenId) - 1
        );
        DataTypes.Point memory oldGaugeVoteWeight;
        DataTypes.Point memory newGaugeVoteWeight;

        // Get the updated gauge vote weight
        newGaugeVoteWeight.bias = PercentageMath.percentMul(
            lockLastPoint.bias -
                (lockLastPoint.slope *
                    (block.timestamp - lockLastPoint.timestamp)),
            ratio
        );
        newGaugeVoteWeight.slope = PercentageMath.percentMul(
            lockLastPoint.slope,
            ratio
        );

        newGaugeVoteWeight.timestamp = block.timestamp;

        // If we already have valid votes in this gauge
        if (
            _lockGaugeVoteRatio[tokenId][gauge] > 0 &&
            block.timestamp < lockedBalance.end
        ) {
            // Get the updated old gauge vote weight
            oldGaugeVoteWeight.bias =
                _lockGaugeVotePoint[tokenId][gauge].slope *
                (block.timestamp -
                    _lockGaugeVotePoint[tokenId][gauge].timestamp);
            oldGaugeVoteWeight.slope = _lockGaugeVotePoint[tokenId][gauge]
                .slope;
            oldGaugeVoteWeight.timestamp = block.timestamp;

            _gaugeWeightSlopeChanges[gauge][
                lockedBalance.end
            ] -= oldGaugeVoteWeight.slope;

            _totalWeightSlopeChanges[lockedBalance.end] -= oldGaugeVoteWeight
                .slope;
        }

        // Add new slope updates
        _gaugeWeightSlopeChanges[gauge][lockedBalance.end] += newGaugeVoteWeight
            .slope;
        _totalWeightSlopeChanges[lockedBalance.end] += newGaugeVoteWeight.slope;

        // Update checkpoints
        _lastGaugeWeigthCheckpoint[gauge].bias =
            _lastGaugeWeigthCheckpoint[gauge].bias -
            (_lastGaugeWeigthCheckpoint[gauge].slope *
                (block.timestamp -
                    _lastGaugeWeigthCheckpoint[gauge].timestamp)) +
            newGaugeVoteWeight.bias -
            oldGaugeVoteWeight.bias;
        _lastGaugeWeigthCheckpoint[gauge].slope =
            _lastGaugeWeigthCheckpoint[gauge].slope +
            newGaugeVoteWeight.slope -
            oldGaugeVoteWeight.slope;
        _lastGaugeWeigthCheckpoint[gauge].timestamp = block.timestamp;

        _lastWeightCheckpoint.bias =
            _lastWeightCheckpoint.bias -
            (_lastWeightCheckpoint.slope *
                (block.timestamp - _lastWeightCheckpoint.timestamp)) +
            newGaugeVoteWeight.bias -
            oldGaugeVoteWeight.bias;
        _lastWeightCheckpoint.slope =
            _lastWeightCheckpoint.slope +
            newGaugeVoteWeight.slope -
            oldGaugeVoteWeight.slope;
        _lastWeightCheckpoint.timestamp = block.timestamp;

        // Update user vote info
        _lockVoteRatio[tokenId] =
            ratio +
            _lockVoteRatio[tokenId] -
            _lockGaugeVoteRatio[tokenId][gauge];
        _lockGaugeVoteRatio[tokenId][gauge] = ratio;
        _lockGaugeVotePoint[tokenId][gauge] = newGaugeVoteWeight;

        emit Vote(msg.sender, tokenId, gauge, ratio);
    }

    /// @notice Returns the maximum amount of tokens that can be distributed as rewards for the specified epoch.
    /// @param epoch The epoch for which to get the rewards.
    /// @return The maximum amount of tokens that can be distributed as rewards for the specified epoch.
    function getRewardsCeiling(uint256 epoch) public pure returns (uint256) {
        uint256 inflationEpoch = epoch / INFLATION_PERIOD;
        // If we are in the loading period, return smaller rewards
        if (epoch < LOADING_PERIOD) {
            return (INITIAL_REWARDS * epoch) / LOADING_PERIOD;
        } else if (inflationEpoch > MAX_INFLATION_PERIODS) {
            // Cap the inflation epoch = stabilize rewards
            inflationEpoch = MAX_INFLATION_PERIODS;
        }

        return
            (INITIAL_REWARDS * (3 ** inflationEpoch)) / (4 ** inflationEpoch);
    }

    /// @notice Returns the amount of tokens to distribute as rewards for the specified epoch.
    /// @dev The amount of tokens to distribute goes down as the number of locked tokens goes up.
    /// @param epoch The epoch for which to get the rewards.
    /// @return The amount of tokens to distribute as rewards for the specified epoch.
    function getEpochRewards(
        uint256 epoch
    ) public noFutureEpoch(epoch) returns (uint256) {
        // If there are no votes in any gauge, return 0
        if (getTotalWeightAt(epoch) == 0) {
            return 0;
        }

        return
            (((PercentageMath.PERCENTAGE_FACTOR -
                (IVotingEscrow(_addressProvider.getVotingEscrow())
                    .getLockedRatioAt(epoch) / 5)) ** 3) *
                getRewardsCeiling(epoch)) /
            (PercentageMath.PERCENTAGE_FACTOR ** 3);
    }

    /// @notice Get the LE reward for a gauge in a given epoch
    /// @param gauge The address of the gauge
    /// @param epoch The epoch to get the reward for
    /// @return rewards The LE reward for the gauge in the given epoch
    function getGaugeRewards(
        address gauge,
        uint256 epoch
    )
        external
        validGauge(gauge)
        noFutureEpoch(epoch)
        returns (uint256 rewards)
    {
        // If there are no votes in any gauge, return 0
        uint256 totalWeight = getTotalWeightAt(epoch);
        if (totalWeight == 0) {
            return 0;
        }

        return
            (getEpochRewards(epoch) * getGaugeWeightAt(gauge, epoch)) /
            totalWeight;
    }

    /// @notice Sets the maturity period for LP tokens
    /// @param maturityPeriod The new maturity period in epochs
    function setLPMaturityPeriod(uint256 maturityPeriod) external onlyOwner {
        require(maturityPeriod > 0, "GC:SLPMP:INVALID_MATURITY_PERIOD");
        _lpMaturityPeriod = maturityPeriod;
    }

    /// @notice Gets the maturity period for LP tokens
    /// @return The maturity period in epochs
    function getLPMaturityPeriod() external view override returns (uint256) {
        return _lpMaturityPeriod;
    }

    function _requireValidGauge(address gauge) internal view {
        require(_isGauge[gauge], "GC:INVALID_GAUGE");
    }

    function _requireLockExists(uint256 tokenId) internal view {
        try
            IERC721Upgradeable(_addressProvider.getVotingEscrow()).ownerOf(
                tokenId
            ) // solhint-disable-next-line no-empty-blocks
        {} catch {
            revert("GC:LOCK_NOT_FOUND");
        }
    }

    function _requireNoFutureEpoch(uint256 epoch) internal view {
        require(
            epoch <=
                IVotingEscrow(_addressProvider.getVotingEscrow()).getEpoch(
                    block.timestamp
                ),
            "GC:FUTURE_EPOCH"
        );
    }
}
