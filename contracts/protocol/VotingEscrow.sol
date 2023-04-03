// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.8.19;

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
import {IERC20MetadataUpgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/IERC20MetadataUpgradeable.sol";
import {PercentageMath} from "../libraries/math/PercentageMath.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "hardhat/console.sol";

/// @title VotingEscrow
/// @notice Provides functionality for locking LE tokens for a specified period of time and is the center of the epoch logic
contract VotingEscrow is
    Initializable,
    ContextUpgradeable,
    IVotingEscrow,
    IERC20MetadataUpgradeable,
    OwnableUpgradeable,
    ReentrancyGuardUpgradeable
{
    uint256 public constant LOCK_FACTOR = 4;
    uint256 public constant MINLOCKTIME = 1 weeks;
    uint256 public constant MAXLOCKTIME = 4 * 365 days;
    uint256 public constant EPOCH_PERIOD = 1 days;

    IAddressesProvider private _addressProvider;
    uint256 _deployTimestamp;
    // Locked balance for each user
    mapping(address => DataTypes.LockedBalance) private _userLockedBalance;
    // History of user ve related actions
    mapping(address => DataTypes.Point[]) private _userHistory;
    // Epoch history of total weight
    uint256[] private _totalWeightHistory;
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

    /// @notice Initializes the VotingEscrow contract.
    /// @param addressProvider The address of the AddressesProvider contract.
    function initialize(
        IAddressesProvider addressProvider
    ) external initializer {
        __Ownable_init();
        _addressProvider = addressProvider;
        _deployTimestamp = block.timestamp;
        _totalWeightHistory.push(0);
        _lastWeightCheckpoint = DataTypes.Point(0, 0, block.timestamp);
    }

    /// @notice Returns the name of the token.
    /// @return The name of the token.
    function name() external view override returns (string memory) {
        return
            string.concat(
                "Vote Escrowed ",
                IERC20MetadataUpgradeable(_addressProvider.getNativeToken())
                    .symbol()
            );
    }

    /// @notice Returns the symbol of the token.
    /// @return The symbol of the token.
    function symbol() external view override returns (string memory) {
        return
            string.concat(
                "ve",
                IERC20MetadataUpgradeable(_addressProvider.getNativeToken())
                    .symbol()
            );
    }

    /// @notice Returns the decimals of the token.
    /// @return The decimals of the token.
    function decimals() external pure override returns (uint8) {
        return 18;
    }

    /// @notice Returns the length of an epoch period in seconds.
    /// @return The length of an epoch period in seconds.
    function epochPeriod() external pure override returns (uint256) {
        return EPOCH_PERIOD;
    }

    /// @notice Returns the epoch number for a given timestamp.
    /// @param timestamp The timestamp for which to retrieve the epoch number.
    /// @return The epoch number.
    function epoch(uint256 timestamp) public view returns (uint256) {
        require(
            timestamp > _deployTimestamp,
            "Timestamp prior to contract deployment"
        );
        return (timestamp / EPOCH_PERIOD) - (_deployTimestamp / EPOCH_PERIOD);
    }

    /// @notice Returns the timestamp of the start of an epoch.
    /// @param _epoch The epoch number for which to retrieve the start timestamp.
    /// @return The start timestamp of the epoch.
    function epochTimestamp(uint256 _epoch) public view returns (uint256) {
        return (_deployTimestamp / EPOCH_PERIOD + _epoch) * EPOCH_PERIOD;
    }

    /// @notice Updates the total weight history array and checkpoint with the current weight.
    /// @dev This function will break if it is not called for 128 epochs.
    function writeTotalWeightHistory() public {
        // Update last saved weight checkpoint and record weight for epochs
        uint256 epochTimestampPointer = epochTimestamp(
            _totalWeightHistory.length
        );
        for (uint256 i = 0; i < 2 ** 7; i++) {
            if (epochTimestampPointer > block.timestamp) {
                break;
            }

            // Save epoch total weight
            uint256 epochTotalWeight = _lastWeightCheckpoint.bias -
                _lastWeightCheckpoint.slope *
                (epochTimestampPointer - _lastWeightCheckpoint.timestamp);
            _totalWeightHistory.push(epochTotalWeight);

            // Update last weight checkpoint
            _lastWeightCheckpoint.bias = epochTotalWeight;
            _lastWeightCheckpoint.timestamp = epochTimestampPointer;
            _lastWeightCheckpoint.slope -= _slopeChanges[epochTimestampPointer];

            //Increase epoch timestamp
            epochTimestampPointer += EPOCH_PERIOD;
        }
    }

    /// @notice Simulates a lock for a given amount of tokens and unlock time.
    /// @param amount The amount of tokens to be locked.
    /// @param end The unlock time for the lock operation.
    /// @return The number of voting escrow tokens that would be minted as a result of the lock operation.
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

        return (amount * (roundedUnlockTime - block.timestamp)) / MAXLOCKTIME;
    }

    /// @notice Updates the global tracking variables and the user's history of locked balances.
    /// @param user The address of the user whose balance is being updated.
    /// @param oldBalance The user's previous locked balance.
    /// @param newBalance The user's new locked balance.
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

    /// @notice Returns the length of the history array for the specified user.
    /// @param user The address of the user whose history array length should be returned.
    /// @return The length of the user's history array.
    function userHistoryLength(
        address user
    ) public view override returns (uint256) {
        return _userHistory[user].length;
    }

    /// @notice Returns the user's history point at a given index.
    /// @param user The user's address.
    /// @param index The index of the history point to retrieve.
    /// @return The user's history point at the given index.
    function getUserHistoryPoint(
        address user,
        uint256 index
    ) public view override returns (DataTypes.Point memory) {
        return _userHistory[user][index];
    }

    /// @notice Returns the total weight of locked tokens at a given epoch.
    /// @param _epoch The epoch number for which to retrieve the total weight.
    /// @return The total weight of locked tokens at the given epoch.
    function totalSupplyAt(uint256 _epoch) external returns (uint256) {
        // Update total weight history
        writeTotalWeightHistory();

        return _totalWeightHistory[_epoch];
    }

    /// @notice Returns the total weight of locked tokens.
    /// @dev Might not return the most up-to-date value if the total weight has not been updated in the current epoch.
    /// @return The total weight of locked tokens.
    function totalSupply() public view override returns (uint256) {
        return
            _lastWeightCheckpoint.bias -
            _lastWeightCheckpoint.slope *
            (block.timestamp - _lastWeightCheckpoint.timestamp);
    }

    /// @notice Returns the weight of locked tokens for a given user.
    /// @param user The account for which to retrieve the locked balance weight.
    /// @return The weight of locked tokens for the given account.
    function balanceOf(address user) public view override returns (uint256) {
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

    /// @dev Locks tokens into the voting escrow contract for a specified amount of time.
    /// @param receiver The address that will receive the locked tokens.
    /// @param amount The amount of tokens to be locked.
    /// @param unlockTime The unlock time for the lock operation.
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

    /// @notice Increases the locked balance of the caller by the given amount and performs a checkpoint
    /// @param amount The amount to increase the locked balance by
    /// @dev Requires the caller to have an active lock on their balance
    /// @dev Transfers the native token from the caller to this contract
    /// @dev Calls a checkpoint event
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

    /// @notice Increases the unlock time of the caller's lock to the given time and performs a checkpoint
    /// @param newUnlockTime The new unlock time to set
    /// @dev Requires the caller to have an active lock on their balance
    /// @dev Requires the new unlock time to be greater than or equal to the current unlock time
    /// @dev Requires the new unlock time to be less than or equal to the maximum lock time
    /// @dev Calls a checkpoint event
    function increaseUnlockTime(uint256 newUnlockTime) external {
        // Round the locktime to whole epochs
        uint256 roundedUnlocktime = (newUnlockTime / EPOCH_PERIOD) *
            EPOCH_PERIOD;
        require(
            _userLockedBalance[_msgSender()].end > block.timestamp,
            "User has no active lock"
        );
        require(
            roundedUnlocktime > _userLockedBalance[_msgSender()].end,
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

    /// @notice Withdraws the locked balance of the caller and performs a checkpoint
    /// @dev Requires the caller to have a non-zero locked balance and an expired lock time
    /// @dev Requires the caller to have no active votes in the gauge controller
    /// @dev Transfers the native token from this contract to the caller
    /// @dev Calls a checkpoint event
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

    /// @notice Returns the current lock object of a given user
    /// @param user The user to get the lock object of
    /// @return The locked object of the user
    function locked(
        address user
    ) external view returns (DataTypes.LockedBalance memory) {
        return _userLockedBalance[user];
    }

    /// @notice ERC20 approve function
    /// @dev Reverts if called
    function approve(address, uint256) public pure override returns (bool) {
        revert("Approve not allowed");
    }

    /// @notice ERC20 allowance function
    /// @dev Reverts if called
    function allowance(
        address,
        address
    ) public pure override returns (uint256) {
        revert("Allowance not allowed");
    }

    /// @notice ERC20 transfer function
    /// @dev Reverts if called
    function transfer(address, uint256) public pure override returns (bool) {
        revert("Transfer not allowed");
    }

    /// @notice ERC20 transferFrom function
    /// @dev Reverts if called
    function transferFrom(
        address,
        address,
        uint256
    ) public pure override returns (bool) {
        revert("TransferFrom not allowed");
    }
}
