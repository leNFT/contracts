// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.8.19;

import {IAddressProvider} from "../../interfaces/IAddressProvider.sol";
import {INativeToken} from "../../interfaces/INativeToken.sol";
import {IGaugeController} from "../../interfaces/IGaugeController.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {DataTypes} from "../../libraries/types/DataTypes.sol";
import {IVotingEscrow} from "../../interfaces/IVotingEscrow.sol";
import {IGauge} from "../../interfaces/IGauge.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {PercentageMath} from "../../libraries/utils/PercentageMath.sol";
import {ERC165} from "@openzeppelin/contracts/utils/introspection/ERC165.sol";

/// @title LendingGauge contract
/// @author leNFT
/// @notice Liquidity Gauge contract. Distributes incentives to users who have deposited into the LendingPool.
/// @dev The gauge tracks the balance and work done by users, which are then used to calculate rewards.
contract LendingGauge is IGauge, ERC165 {
    IAddressProvider private immutable _addressProvider;
    address private immutable _lpToken;
    mapping(address => uint256) private _balanceOf;
    mapping(address => DataTypes.WorkingBalance[])
        private _workingBalanceHistory;
    mapping(address => uint256) private _workingBalancePointer;
    mapping(address => uint256) private _userNextClaimableEpoch;
    uint256 private _workingWeight;
    uint256[] private _workingWeightHistory;

    using SafeERC20 for IERC20;

    event Deposit(address indexed user, uint256 amount);
    event Withdraw(address indexed user, uint256 amount);

    /// @notice Constructor function for LendingGauge
    /// @param addressProvider The address provider contract
    /// @param lpToken_ The address of the LendingPool token
    constructor(IAddressProvider addressProvider, address lpToken_) {
        _addressProvider = addressProvider;
        _lpToken = lpToken_;
        _workingWeightHistory = [0];
    }

    /// @notice Returns the address of the LendingPool token
    /// @return The address of the LendingPool token
    function getLPToken() external view returns (address) {
        return _lpToken;
    }

    /// @notice Returns the total supply of the LendingPool token in the contract
    /// @return The total supply of the LendingPool token in the contract
    function getTotalSupply() public view returns (uint256) {
        return IERC20(_lpToken).balanceOf(address(this));
    }

    /// @notice Returns the balance of staked LP tokens for a given user
    /// @param user The address of the user to check balance for
    /// @return The balance of the user
    function getBalanceOf(address user) external view returns (uint256) {
        return _balanceOf[user];
    }

    /// @notice Claims the gauge rewards for the user and updates the user's next claimable epoch
    /// @dev Will give a maximum of 50 epochs worth of rewards
    /// @return amountToClaim The amount of gauge rewards claimed
    function claim() external returns (uint256 amountToClaim) {
        _checkpoint(msg.sender);

        IVotingEscrow votingEscrow = IVotingEscrow(
            _addressProvider.getVotingEscrow()
        );
        IGaugeController gaugeController = IGaugeController(
            _addressProvider.getGaugeController()
        );

        // Get maximum number of user epochs
        uint256 workingBalanceHistoryLength = _workingBalanceHistory[msg.sender]
            .length;

        // Check if user has any user actions and therefore something to claim
        if (workingBalanceHistoryLength == 0) {
            return 0;
        }

        // Set the next claimable epoch if it's the first time the user claims
        if (_userNextClaimableEpoch[msg.sender] == 0) {
            _userNextClaimableEpoch[msg.sender] =
                votingEscrow.getEpoch(
                    _workingBalanceHistory[msg.sender][0].timestamp
                ) +
                1;
        }
        // Iterate over a max of 50 epochs and/or user epochs
        uint256 nextClaimableEpoch = _userNextClaimableEpoch[msg.sender];
        uint256 currentEpoch = votingEscrow.getEpoch(block.timestamp);
        for (uint256 i = 0; i < 50 && nextClaimableEpoch < currentEpoch; ) {
            // Get the current user working Balance and its epoch
            DataTypes.WorkingBalance
                memory workingBalance = _workingBalanceHistory[msg.sender][
                    _workingBalancePointer[msg.sender]
                ];

            // Check if the user entire balance history has been iterated
            // This should never be the case since the checkpoint function is called before this function and it pushes one working balance to the history
            if (
                _workingBalancePointer[msg.sender] ==
                workingBalanceHistoryLength - 1
            ) {
                if (_workingWeightHistory[nextClaimableEpoch] > 0) {
                    amountToClaim +=
                        (gaugeController.getGaugeRewards(
                            address(this),
                            nextClaimableEpoch
                        ) *
                            workingBalance.weight *
                            _maturityMultiplier(
                                block.timestamp - workingBalance.timestamp
                            )) /
                        (_workingWeightHistory[nextClaimableEpoch] *
                            PercentageMath.PERCENTAGE_FACTOR);
                }

                nextClaimableEpoch++;
            } else {
                // We haven't iterated over the entire user history
                DataTypes.WorkingBalance
                    memory nextWorkingBalance = _workingBalanceHistory[
                        msg.sender
                    ][_workingBalancePointer[msg.sender] + 1];

                // Check if the next working balance is in the same epoch as the current working balance
                if (
                    votingEscrow.getEpoch(nextWorkingBalance.timestamp) ==
                    votingEscrow.getEpoch(workingBalance.timestamp)
                ) {
                    _workingBalancePointer[msg.sender]++;
                }
                // Check if the next working balance is in the next claimable epoch
                else if (
                    votingEscrow.getEpoch(nextWorkingBalance.timestamp) ==
                    nextClaimableEpoch
                ) {
                    // If the next working balance has no decrease in balance we can claim the rewards
                    if (
                        _workingWeightHistory[nextClaimableEpoch] > 0 &&
                        workingBalance.amount <= nextWorkingBalance.amount
                    ) {
                        amountToClaim +=
                            (gaugeController.getGaugeRewards(
                                address(this),
                                nextClaimableEpoch
                            ) *
                                _maturityMultiplier(
                                    nextWorkingBalance.timestamp -
                                        workingBalance.timestamp
                                ) *
                                workingBalance.weight) /
                            (_workingWeightHistory[nextClaimableEpoch] *
                                PercentageMath.PERCENTAGE_FACTOR);
                    }
                    _workingBalancePointer[msg.sender]++;
                    nextClaimableEpoch++;
                } else {
                    // THe next working balance is not in the next claimable epoch
                    if (_workingWeightHistory[nextClaimableEpoch] > 0) {
                        amountToClaim +=
                            (gaugeController.getGaugeRewards(
                                address(this),
                                nextClaimableEpoch
                            ) *
                                _maturityMultiplier(
                                    nextWorkingBalance.timestamp -
                                        workingBalance.timestamp
                                ) *
                                workingBalance.weight) /
                            (_workingWeightHistory[nextClaimableEpoch] *
                                PercentageMath.PERCENTAGE_FACTOR);
                    }
                    nextClaimableEpoch++;
                }
            }

            unchecked {
                ++i;
            }
        }

        _userNextClaimableEpoch[msg.sender] = nextClaimableEpoch;

        // Claim the rewards if there are any
        if (amountToClaim > 0) {
            INativeToken(_addressProvider.getNativeToken()).mintGaugeRewards(
                msg.sender,
                amountToClaim
            );

            emit Claim(msg.sender, amountToClaim);
        }
    }

    /// @notice Updates the total weight history by recording the current total weight for the current epoch and 128 previous epochs.
    /// @dev This function will break if it is not used for 128 epochs in a row.
    function writeTotalWeightHistory() public {
        // Update last saved weight checkpoint and record weight for epochs
        // Will break if is not used for 128 epochs
        uint256 currentEpoch = IVotingEscrow(_addressProvider.getVotingEscrow())
            .getEpoch(block.timestamp);
        for (uint256 i = 0; i < 2 ** 7; i++) {
            //Increase epoch
            if (_workingWeightHistory.length >= currentEpoch) {
                break;
            }

            // Save epoch total weight
            _workingWeightHistory.push(_workingWeight);
        }
    }

    /// @notice Gets the maturity boost for a given time interval since inception
    /// @param timeInterval The time interval to get the boost for.
    /// @return The maturity boost.
    function _maturityMultiplier(
        uint256 timeInterval
    ) internal view returns (uint256) {
        uint256 lpMaturityPeriod = IGaugeController(
            _addressProvider.getGaugeController()
        ).getLPMaturityPeriod();
        if (timeInterval > lpMaturityPeriod) {
            return PercentageMath.PERCENTAGE_FACTOR;
        } else {
            return
                (PercentageMath.PERCENTAGE_FACTOR * timeInterval) /
                lpMaturityPeriod;
        }
    }

    /// @notice Updates the working balance of a user by computing the new amount based on the user's voting balance and the total voting supply.
    /// @dev This function also saves the total weight history and the user's working balance history.
    /// @param user The address of the user.
    function _checkpoint(address user) internal {
        // Get user ve balance and total ve balance
        IVotingEscrow votingEscrow = IVotingEscrow(
            _addressProvider.getVotingEscrow()
        );

        // Make sure the voting escrow's total supply is up to date
        IVotingEscrow(votingEscrow).writeTotalWeightHistory();

        uint256 userVotingBalance = votingEscrow.getUserWeight(user);
        uint256 totalVotingSupply = votingEscrow.getTotalWeight();
        uint256 newWeight;

        // Save the total weight history
        writeTotalWeightHistory();

        if (totalVotingSupply == 0) {
            newWeight = _balanceOf[user];
        } else {
            newWeight = Math.min(
                _balanceOf[user],
                (PercentageMath.HALF_PERCENTAGE_FACTOR *
                    _balanceOf[user] +
                    (PercentageMath.HALF_PERCENTAGE_FACTOR *
                        userVotingBalance *
                        getTotalSupply()) /
                    totalVotingSupply) / PercentageMath.PERCENTAGE_FACTOR
            );
        }

        uint256 oldWorkingBalanceWeight;
        if (_workingBalanceHistory[user].length > 0) {
            oldWorkingBalanceWeight = _workingBalanceHistory[user][
                _workingBalanceHistory[user].length - 1
            ].weight;
        }
        DataTypes.WorkingBalance memory newWorkingBalance = DataTypes
            .WorkingBalance({
                amount: _balanceOf[user],
                weight: newWeight,
                timestamp: block.timestamp
            });

        _workingWeight =
            _workingWeight +
            newWorkingBalance.weight -
            oldWorkingBalanceWeight;

        _workingBalanceHistory[user].push(newWorkingBalance);
    }

    /// @notice Computes the boost of a user based on their working balance and their balance.
    /// @param user The address of the user.
    /// @return The boost of the user.
    function getUserBoost(address user) external view returns (uint256) {
        if (_balanceOf[user] == 0) {
            return 0;
        }

        return
            (2 *
                _workingBalanceHistory[user][
                    _workingBalanceHistory[user].length - 1
                ].weight *
                PercentageMath.PERCENTAGE_FACTOR) / _balanceOf[user];
    }

    /// @notice Returns the current maturity boost for a user
    /// @param user The address of the user whose maturity boost will be returned.
    /// @return The current maturity boost for the user.
    function getUserMaturityMultiplier(
        address user
    ) external view returns (uint256) {
        uint256 workingBalanceHistoryLength = _workingBalanceHistory[user]
            .length;
        if (workingBalanceHistoryLength == 0) {
            return 0;
        }

        return
            _maturityMultiplier(
                block.timestamp -
                    _workingBalanceHistory[user][
                        workingBalanceHistoryLength - 1
                    ].timestamp
            );
    }

    /// @notice Updates the working balance of a user if one of their locks has expired.
    /// @param tokenId The tokenId of the user's lock that has expired.
    function kick(uint256 tokenId) external {
        address votingEscrowAddress = _addressProvider.getVotingEscrow();
        // Get user locked balance end time
        uint256 lockEnd = IVotingEscrow(votingEscrowAddress)
            .getLock(tokenId)
            .end;

        if (lockEnd < block.timestamp) {
            _checkpoint(IERC721(votingEscrowAddress).ownerOf(tokenId));
        }
    }

    /// @notice Deposits LP tokens into the contract and updates the user's balance and working balance.
    /// @param amount The amount of LP tokens to deposit.
    function deposit(uint256 amount) external {
        require(amount > 0, "LG:D:AMOUNT_ZERO");

        // Update balance
        _balanceOf[msg.sender] += amount;

        IERC20(_lpToken).safeTransferFrom(msg.sender, address(this), amount);

        _checkpoint(msg.sender);

        emit Deposit(msg.sender, amount);
    }

    /// @notice Withdraws LP tokens from the contract and updates the user's balance and working balance.
    /// @param amount The amount of LP tokens to withdraw.
    function withdraw(uint256 amount) external {
        require(
            amount <= _balanceOf[msg.sender],
            "LG:W:AMOUNT_EXCEEDS_BALANCE"
        );

        // Update balance
        _balanceOf[msg.sender] -= amount;

        IERC20(_lpToken).safeTransfer(msg.sender, amount);

        _checkpoint(msg.sender);

        emit Withdraw(msg.sender, amount);
    }

    function supportsInterface(
        bytes4 interfaceId
    ) public view virtual override(ERC165) returns (bool) {
        return
            interfaceId == type(IGauge).interfaceId ||
            ERC165.supportsInterface(interfaceId);
    }
}
