// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.8.19;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {MathUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/math/MathUpgradeable.sol";
import {IAddressesProvider} from "../interfaces/IAddressesProvider.sol";
import {CountersUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/CountersUpgradeable.sol";
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
import {IERC20MetadataUpgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/IERC20MetadataUpgradeable.sol";
import {ERC165Upgradeable} from "@openzeppelin/contracts-upgradeable/utils/introspection/ERC165Upgradeable.sol";
import {IERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import {ERC721Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC721/ERC721Upgradeable.sol";
import {ERC721EnumerableUpgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC721/extensions/ERC721EnumerableUpgradeable.sol";
import {PercentageMath} from "../libraries/math/PercentageMath.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "hardhat/console.sol";

/// @title VotingEscrow
/// @notice Provides functionality for locking LE tokens for a specified period of time and is the center of the epoch logic
contract VotingEscrow is
    Initializable,
    ContextUpgradeable,
    IVotingEscrow,
    ERC165Upgradeable,
    ERC721Upgradeable,
    ERC721EnumerableUpgradeable,
    OwnableUpgradeable,
    ReentrancyGuardUpgradeable
{
    uint256 public constant LOCK_FACTOR = 4;
    uint256 public constant MINLOCKTIME = 1 weeks;
    uint256 public constant MAXLOCKTIME = 4 * 365 days;
    uint256 public constant EPOCH_PERIOD = 1 days;

    IAddressesProvider private _addressProvider;
    uint256 _deployTimestamp;
    // Locked balance for each lock
    mapping(uint256 => DataTypes.LockedBalance) private _lockedBalance;
    // History of actions for each lock
    mapping(uint256 => DataTypes.Point[]) private _lockHistory;
    // Epoch history of total weight
    uint256[] private _totalWeightHistory;
    // Epoch history of locked ratio
    uint256[] private _lockedRatioHistory;
    // Last checkpoint for the total weight
    DataTypes.Point _lastWeightCheckpoint;
    // Slope Changes per timestamp
    mapping(uint256 => uint256) private _slopeChanges;
    CountersUpgradeable.Counter private _tokenIdCounter;

    using CountersUpgradeable for CountersUpgradeable.Counter;
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
        __ERC721_init(
            string.concat(
                "Vote Escrowed ",
                IERC20MetadataUpgradeable(_addressProvider.getNativeToken())
                    .symbol()
            ),
            string.concat(
                "ve",
                IERC20MetadataUpgradeable(_addressProvider.getNativeToken())
                    .symbol()
            )
        );
        __ERC721Enumerable_init();
        __Ownable_init();
        _addressProvider = addressProvider;
        _deployTimestamp = block.timestamp;
        _totalWeightHistory.push(0);
        _lastWeightCheckpoint = DataTypes.Point(0, 0, block.timestamp);
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

            // Update total locked ratio
            _lockedRatioHistory.push(
                (IERC20Upgradeable(_addressProvider.getNativeToken()).balanceOf(
                    address(this)
                ) * PercentageMath.PERCENTAGE_FACTOR) /
                    IERC20Upgradeable(_addressProvider.getNativeToken())
                        .totalSupply()
            );

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
    /// @param tokenId The veLock token id whose balance is being updated.
    /// @param oldBalance The user's previous locked balance.
    /// @param newBalance The user's new locked balance.
    function _checkpoint(
        uint256 tokenId,
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
        _lockHistory[tokenId].push(newPoint);
    }

    /// @notice Returns the length of the history array for the specified user.
    /// @param tokenId The token id of the lock for which to retrieve the history length.
    /// @return The length of the user's history array.
    function lockHistoryLength(
        uint256 tokenId
    ) public view override returns (uint256) {
        return _lockHistory[tokenId].length;
    }

    /// @notice Returns the user's history point at a given index.
    /// @param tokenId The token id of the lock for which to retrieve the history point.
    /// @param index The index of the history point to retrieve.
    /// @return The user's history point at the given index.
    function getLockHistoryPoint(
        uint256 tokenId,
        uint256 index
    ) public view override returns (DataTypes.Point memory) {
        return _lockHistory[tokenId][index];
    }

    function getLockedRatioAt(
        uint256 _epoch
    ) external view override returns (uint256) {
        return _lockedRatioHistory[_epoch];
    }

    /// @notice Returns the total weight of locked tokens at a given epoch.
    /// @param _epoch The epoch number for which to retrieve the total weight.
    /// @return The total weight of locked tokens at the given epoch.
    function totalWeightAt(uint256 _epoch) external returns (uint256) {
        // Update total weight history
        writeTotalWeightHistory();

        return _totalWeightHistory[_epoch];
    }

    /// @notice Returns the total weight of locked tokens.
    /// @dev Might not return the most up-to-date value if the total weight has not been updated in the current epoch.
    /// @return The total weight of locked tokens.
    function totalWeight() public view returns (uint256) {
        return
            _lastWeightCheckpoint.bias -
            _lastWeightCheckpoint.slope *
            (block.timestamp - _lastWeightCheckpoint.timestamp);
    }

    /// @notice Returns the weight of locked tokens for a given lock.
    /// @param tokenId The tokenid for which to retrieve the locked balance weight.
    /// @return The weight of locked tokens for the given account.
    function lockWeight(uint256 tokenId) public view returns (uint256) {
        // If the locked token end time has passed
        if (_lockedBalance[tokenId].end < block.timestamp) {
            return 0;
        }
        DataTypes.Point memory lastUserPoint = _lockHistory[tokenId][
            _lockHistory[tokenId].length - 1
        ];

        return
            lastUserPoint.bias -
            lastUserPoint.slope *
            (block.timestamp - lastUserPoint.timestamp);
    }

    function userWeight(address user) external view returns (uint256) {
        uint256 balance = 0;
        uint256 length = balanceOf(user);
        for (uint256 i = 0; i < length; i++) {
            balance += lockWeight(tokenOfOwnerByIndex(user, i));
        }
        return balance;
    }

    /// @dev Locks tokens into the voting escrow contract for a specified amount of time.
    /// @param receiver The address that will receive the locked tokens.
    /// @param amount The amount of tokens to be locked.
    /// @param unlockTime The unlock time for the lock operation.
    function createLock(
        address receiver,
        uint256 amount,
        uint256 unlockTime
    ) external nonReentrant {
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

        // Mint a veNFT to represent the lock and increase the token id counter
        uint256 tokenId = _tokenIdCounter.current();
        _safeMint(receiver, tokenId);
        _tokenIdCounter.increment();

        // Save oldLocked and update the locked balance
        DataTypes.LockedBalance memory oldLocked = _lockedBalance[tokenId];
        _lockedBalance[tokenId].init(amount, roundedUnlockTime);

        // Call a checkpoint and update global tracking vars
        _checkpoint(tokenId, oldLocked, _lockedBalance[tokenId]);

        IERC20Upgradeable(_addressProvider.getNativeToken()).safeTransferFrom(
            _msgSender(),
            address(this),
            amount
        );
    }

    /// @notice Increases the locked balance of the caller by the given amount and performs a checkpoint
    /// @param tokenId The token id of the lock to increase the amount of
    /// @param amount The amount to increase the locked balance by
    /// @dev Requires the caller to have an active lock on their balance
    /// @dev Transfers the native token from the caller to this contract
    /// @dev Calls a checkpoint event
    function increaseAmount(
        uint256 tokenId,
        uint256 amount
    ) external nonReentrant {
        require(_lockedBalance[tokenId].end > block.timestamp, "Inactive Lock");
        require(ownerOf(tokenId) == _msgSender(), "Not the owner of the lock");

        // Save oldLocked and update the locked balance
        DataTypes.LockedBalance memory oldLocked = _lockedBalance[tokenId];
        _lockedBalance[tokenId].amount += amount;

        // Call a checkpoint and update global tracking vars
        _checkpoint(tokenId, oldLocked, _lockedBalance[tokenId]);

        IERC20Upgradeable(_addressProvider.getNativeToken()).safeTransferFrom(
            _msgSender(),
            address(this),
            amount
        );
    }

    /// @notice Increases the unlock time of the caller's lock to the given time and performs a checkpoint
    /// @param tokenId The token id of the lock to increase the unlock time of
    /// @param newUnlockTime The new unlock time to set
    /// @dev Requires the caller to have an active lock on their balance
    /// @dev Requires the new unlock time to be greater than or equal to the current unlock time
    /// @dev Requires the new unlock time to be less than or equal to the maximum lock time
    /// @dev Calls a checkpoint event
    function increaseUnlockTime(
        uint256 tokenId,
        uint256 newUnlockTime
    ) external nonReentrant {
        // Round the locktime to whole epochs
        uint256 roundedUnlocktime = (newUnlockTime / EPOCH_PERIOD) *
            EPOCH_PERIOD;
        require(ownerOf(tokenId) == _msgSender(), "Not the owner of the lock");
        require(_lockedBalance[tokenId].end > block.timestamp, "Inactive Lock");
        require(
            roundedUnlocktime > _lockedBalance[tokenId].end,
            "Lock time can only increase"
        );

        require(
            roundedUnlocktime <= MAXLOCKTIME + block.timestamp,
            "Locktime higher than maximum locktime"
        );

        // Save oldLocked and update the locked balance
        DataTypes.LockedBalance memory oldLocked = _lockedBalance[tokenId];
        _lockedBalance[tokenId].end = roundedUnlocktime;

        // Call a checkpoint and update global tracking vars
        _checkpoint(tokenId, oldLocked, _lockedBalance[tokenId]);
    }

    /// @notice Withdraws the locked balance of the caller and performs a checkpoint
    /// @param tokenId The token id of the lock to withdraw from
    /// @dev Requires the caller to have a non-zero locked balance and an expired lock time
    /// @dev Requires the caller to have no active votes in the gauge controller
    /// @dev Transfers the native token from this contract to the caller
    /// @dev Calls a checkpoint event
    function withdraw(uint256 tokenId) external {
        require(ownerOf(tokenId) == _msgSender(), "Not the owner of the lock");
        require(_lockedBalance[tokenId].amount > 0, "Nothing to withdraw");
        require(
            block.timestamp > _lockedBalance[tokenId].end,
            "Locktime is not over"
        );

        // Make sure the user has no active votes
        require(
            IGaugeController(_addressProvider.getGaugeController())
                .userVoteRatio(_msgSender()) == 0,
            "User has active gauge votes"
        );

        // Save oldLocked and update the locked balance
        DataTypes.LockedBalance memory oldLocked = _lockedBalance[tokenId];
        delete _lockedBalance[tokenId];

        // Call a checkpoint and update global tracking vars
        _checkpoint(tokenId, oldLocked, _lockedBalance[tokenId]);

        // Send locked amount back to user
        IERC20Upgradeable(_addressProvider.getNativeToken()).safeTransfer(
            _msgSender(),
            oldLocked.amount
        );

        // Burn the veNFT
        _burn(tokenId);
    }

    /// @notice Returns the details for a single lock
    /// @param tokenId The token id of the lock to get the locked balance of and end time of
    /// @return The locked object of the user
    function locked(
        uint256 tokenId
    ) external view returns (DataTypes.LockedBalance memory) {
        return _lockedBalance[tokenId];
    }

    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 tokenId,
        uint256 batchSize
    ) internal override(ERC721Upgradeable, ERC721EnumerableUpgradeable) {
        require(
            false == false,
            "Cannot transfer token - currently locked in an active loan"
        );
        ERC721EnumerableUpgradeable._beforeTokenTransfer(
            from,
            to,
            tokenId,
            batchSize
        );
    }

    function supportsInterface(
        bytes4 interfaceId
    )
        public
        view
        override(
            ERC721EnumerableUpgradeable,
            ERC721Upgradeable,
            ERC165Upgradeable
        )
        returns (bool)
    {
        return
            ERC721EnumerableUpgradeable.supportsInterface(interfaceId) ||
            ERC165Upgradeable.supportsInterface(interfaceId);
    }
}
