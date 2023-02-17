// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.8.17;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {MathUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/math/MathUpgradeable.sol";
import {IAddressesProvider} from "../interfaces/IAddressesProvider.sol";
import {IVotingEscrow} from "../interfaces/IVotingEscrow.sol";
import {IGaugeController} from "../interfaces/IGaugeController.sol";
import {INativeToken} from "../interfaces/INativeToken.sol";
import {ILoanCenter} from "../interfaces/ILoanCenter.sol";
import {INFTOracle} from "../interfaces/INFTOracle.sol";
import {ITokenOracle} from "../interfaces/ITokenOracle.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {SafeERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import {ValidationLogic} from "../libraries/logic/ValidationLogic.sol";
import {ContextUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ContextUpgradeable.sol";
import {DataTypes} from "../libraries/types/DataTypes.sol";
import {LockLogic} from "../libraries/logic/LockLogic.sol";
import {ConfigTypes} from "../libraries/types/ConfigTypes.sol";
import {IERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import {PercentageMath} from "../libraries/math/PercentageMath.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "hardhat/console.sol";

contract VotingEscrow is
    Initializable,
    ContextUpgradeable,
    IVotingEscrow,
    OwnableUpgradeable,
    ReentrancyGuardUpgradeable
{
    uint256 public constant LOCK_FACTOR = 4;
    uint256 public constant MINLOCKTIME = 1 weeks;
    uint256 public constant MAXLOCKTIME = 4 * 365 days;
    uint256 public constant EPOCH_PERIOD = 1 hours;

    IAddressesProvider private _addressProvider;
    uint256 _deployTimestamp;
    // Locked balance for each user
    mapping(address => DataTypes.LockedBalance) private _userLockedBalance;
    // History of user ve related actions
    mapping(address => DataTypes.Point[]) private _userHistory;
    // Epoch history of total weight
    uint256[] private _totalWeigthHistory;
    // Last checkpoint for the total weight
    DataTypes.Point _lastWeightCheckpoint;
    // Slope Changes per timestamp
    mapping(uint256 => uint256) private _slopeChanges;

    using SafeERC20Upgradeable for IERC20Upgradeable;
    using LockLogic for DataTypes.LockedBalance;

    modifier onlyMarket() {
        require(
            _msgSender() == _addressProvider.getLendingMarket(),
            "Caller must be Market contract"
        );
        _;
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        IAddressesProvider addressProvider
    ) external initializer {
        __Ownable_init();
        _addressProvider = addressProvider;
        _deployTimestamp = block.timestamp;
        _totalWeigthHistory.push(0);
        _lastWeightCheckpoint = DataTypes.Point(0, 0, block.timestamp);
    }

    function epochPeriod() external pure override returns (uint256) {
        return EPOCH_PERIOD;
    }

    function epoch(uint256 timestamp) public view returns (uint256) {
        require(
            timestamp > _deployTimestamp,
            "Timestamp before contract deployment"
        );
        return (timestamp / EPOCH_PERIOD) - (_deployTimestamp / EPOCH_PERIOD);
    }

    function epochTimestamp(uint256 _epoch) public view returns (uint256) {
        return (_deployTimestamp / EPOCH_PERIOD + _epoch) * EPOCH_PERIOD;
    }

    function writeTotalWeightHistory() public {
        // Update last saved weight checkpoint and record weight for epochs
        // Will break if is not used for 128 epochs
        uint256 epochTimestampPointer = epochTimestamp(
            _totalWeigthHistory.length
        );
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
            _lastWeightCheckpoint.slope -= _slopeChanges[epochTimestampPointer];

            //Increase epoch timestamp
            epochTimestampPointer += EPOCH_PERIOD;
        }
    }

    function simulateLock(
        uint256 amount,
        uint256 end
    ) external view returns (uint256) {
        // Round the locktime to whole epochs
        uint256 roundedUnlockTime = (end / EPOCH_PERIOD) * EPOCH_PERIOD;

        require(
            roundedUnlockTime >= MINLOCKTIME + block.timestamp,
            "Locktime smaller than minimum locktime"
        );
        require(
            roundedUnlockTime <= MAXLOCKTIME + block.timestamp,
            "Locktime higher than maximum locktime"
        );

        return amount * ((roundedUnlockTime - block.timestamp) / MAXLOCKTIME);
    }

    function _checkpoint(
        address user,
        DataTypes.LockedBalance memory oldBalance,
        DataTypes.LockedBalance memory newBalance
    ) internal {
        DataTypes.Point memory oldPoint;
        DataTypes.Point memory newPoint;

        // Bring epoch records into the present
        writeTotalWeightHistory();

        // Calculate slopes and bias
        if (oldBalance.end > block.timestamp && oldBalance.amount > 0) {
            oldPoint.slope = oldBalance.amount / MAXLOCKTIME;
            oldPoint.bias = oldPoint.slope * (oldBalance.end - block.timestamp);
        }
        if (newBalance.end > block.timestamp && newBalance.amount > 0) {
            newPoint.slope = newBalance.amount / MAXLOCKTIME;
            newPoint.bias = newPoint.slope * (newBalance.end - block.timestamp);
            newPoint.timestamp = block.timestamp;
        }

        // Update last saved total weight
        _lastWeightCheckpoint.bias =
            _lastWeightCheckpoint.bias -
            _lastWeightCheckpoint.slope *
            (block.timestamp - _lastWeightCheckpoint.timestamp) +
            newPoint.bias -
            oldPoint.bias;
        _lastWeightCheckpoint.slope =
            _lastWeightCheckpoint.slope +
            newPoint.slope -
            oldPoint.slope;
        _lastWeightCheckpoint.timestamp = block.timestamp;

        // Read and update slope changes in accordance
        if (oldBalance.end > block.timestamp) {
            // Cancel old slope change
            _slopeChanges[oldBalance.end] -= oldPoint.slope;
        }

        if (newBalance.end > block.timestamp) {
            _slopeChanges[newBalance.end] += newPoint.slope;
        }

        // Update user history
        _userHistory[user].push(newPoint);
    }

    function userHistoryLength(
        address user
    ) public view override returns (uint256) {
        return _userHistory[user].length;
    }

    function getUserHistoryPoint(
        address user,
        uint256 index
    ) public view override returns (DataTypes.Point memory) {
        return _userHistory[user][index];
    }

    function totalSupplyAt(uint256 _epoch) external returns (uint256) {
        // Update total weight history
        writeTotalWeightHistory();

        return _totalWeigthHistory[_epoch];
    }

    function totalSupply() public returns (uint256) {
        // Update total weight history
        writeTotalWeightHistory();

        return
            _lastWeightCheckpoint.bias -
            _lastWeightCheckpoint.slope *
            (block.timestamp - _lastWeightCheckpoint.timestamp);
    }

    function balanceOf(address user) public view returns (uint256) {
        // If the locked token end time has passed
        if (_userLockedBalance[user].end < block.timestamp) {
            return 0;
        }
        DataTypes.Point memory lastUserPoint = _userHistory[user][
            _userHistory[user].length - 1
        ];

        return
            lastUserPoint.bias -
            lastUserPoint.slope *
            (block.timestamp - lastUserPoint.timestamp);
    }

    // Locks LE tokens into the contract
    function createLock(
        address receiver,
        uint256 amount,
        uint256 unlockTime
    ) external {
        // Round the locktime to whole epochs
        uint256 roundedUnlockTime = (unlockTime / EPOCH_PERIOD) * EPOCH_PERIOD;

        require(
            roundedUnlockTime >= MINLOCKTIME + block.timestamp,
            "Locktime smaller than minimum locktime"
        );
        require(
            roundedUnlockTime <= MAXLOCKTIME + block.timestamp,
            "Locktime higher than maximum locktime"
        );
        require(
            _userLockedBalance[receiver].amount == 0,
            "Receiver has lock with non-zero balance"
        );

        // Save oldLocked and update the locked balance
        DataTypes.LockedBalance memory oldLocked = _userLockedBalance[receiver];
        _userLockedBalance[receiver].init(amount, roundedUnlockTime);

        // Call a checkpoint and update global tracking vars
        _checkpoint(receiver, oldLocked, _userLockedBalance[receiver]);

        IERC20Upgradeable(_addressProvider.getNativeToken()).safeTransferFrom(
            _msgSender(),
            address(this),
            amount
        );
    }

    function increaseAmount(uint256 amount) external {
        require(
            _userLockedBalance[_msgSender()].end > block.timestamp,
            "User has no active lock"
        );

        // Save oldLocked and update the locked balance
        DataTypes.LockedBalance memory oldLocked = _userLockedBalance[
            _msgSender()
        ];
        _userLockedBalance[_msgSender()].amount += amount;

        // Call a checkpoint and update global tracking vars
        _checkpoint(_msgSender(), oldLocked, _userLockedBalance[_msgSender()]);

        IERC20Upgradeable(_addressProvider.getNativeToken()).safeTransferFrom(
            _msgSender(),
            address(this),
            amount
        );
    }

    function increaseUnlockTime(uint256 newUnlockTime) external {
        // Round the locktime to whole epochs
        uint256 roundedUnlocktime = (newUnlockTime / EPOCH_PERIOD) *
            EPOCH_PERIOD;
        require(
            _userLockedBalance[_msgSender()].end > block.timestamp,
            "User has no active lock"
        );
        require(
            roundedUnlocktime >= _userLockedBalance[_msgSender()].end,
            "Lock time can only increase"
        );

        require(
            roundedUnlocktime <= MAXLOCKTIME + block.timestamp,
            "Locktime higher than maximum locktime"
        );

        // Save oldLocked and update the locked balance
        DataTypes.LockedBalance memory oldLocked = _userLockedBalance[
            _msgSender()
        ];
        _userLockedBalance[_msgSender()].end = roundedUnlocktime;

        // Call a checkpoint and update global tracking vars
        _checkpoint(_msgSender(), oldLocked, _userLockedBalance[_msgSender()]);
    }

    function withdraw() external {
        require(
            _userLockedBalance[_msgSender()].amount > 0,
            "Nothing to withdraw"
        );
        require(
            block.timestamp > _userLockedBalance[_msgSender()].end,
            "Locktime is not over"
        );

        // Make sure the user has no active votes
        require(
            IGaugeController(_addressProvider.getGaugeController())
                .userVoteRatio(_msgSender()) == 0,
            "User has active  gauge votes"
        );

        // Save oldLocked and update the locked balance
        DataTypes.LockedBalance memory oldLocked = _userLockedBalance[
            _msgSender()
        ];
        delete _userLockedBalance[_msgSender()];

        // Call a checkpoint and update global tracking vars
        _checkpoint(_msgSender(), oldLocked, _userLockedBalance[_msgSender()]);

        // Send locked amount back to user
        IERC20Upgradeable(_addressProvider.getNativeToken()).safeTransfer(
            _msgSender(),
            oldLocked.amount
        );
    }

    function locked(
        address user
    ) external view returns (DataTypes.LockedBalance memory) {
        return _userLockedBalance[user];
    }
}
