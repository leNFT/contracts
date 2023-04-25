// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.8.19;

import {IAddressesProvider} from "../../interfaces/IAddressesProvider.sol";
import {INativeToken} from "../../interfaces/INativeToken.sol";
import {IGaugeController} from "../../interfaces/IGaugeController.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {DataTypes} from "../../libraries/types/DataTypes.sol";
import {IVotingEscrow} from "../../interfaces/IVotingEscrow.sol";
import {IGauge} from "../../interfaces/IGauge.sol";
import "hardhat/console.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {PercentageMath} from "../../libraries/math/PercentageMath.sol";

/// @title LendingGauge contract
/// @notice Liquidity Gauge contract. Distributes incentives to users who have deposited into the LendingPool.
/// @dev The gauge tracks the balance and work done by users, which are then used to calculate rewards.
contract LendingGauge is IGauge {
    IAddressesProvider private _addressProvider;
    mapping(address => uint256) private _balanceOf;
    mapping(address => DataTypes.WorkingBalance[])
        private _workingBalanceHistory;
    mapping(address => uint256) private _workingBalancePointer;
    mapping(address => uint256) private _userNextClaimableEpoch;
    uint256 private _workingWeight;
    uint256[] private _workingWeightHistory;
    address private _lpToken;

    using SafeERC20 for IERC20;

    /// @notice Constructor function for LendingGauge
    /// @param addressProvider The address provider contract
    /// @param lpToken_ The address of the LendingPool token
    constructor(IAddressesProvider addressProvider, address lpToken_) {
        _addressProvider = addressProvider;
        _lpToken = lpToken_;
        _workingWeightHistory = [0];
    }

    /// @notice Returns the address of the LendingPool token
    /// @return The address of the LendingPool token
    function lpToken() external view returns (address) {
        return _lpToken;
    }

    /// @notice Returns the total supply of the LendingPool token in the contract
    /// @return The total supply of the LendingPool token in the contract
    function totalSupply() public view returns (uint256) {
        return IERC20(_lpToken).balanceOf(address(this));
    }

    /// @notice Returns the balance of staked LP tokens for a given user
    /// @param user The address of the user to check balance for
    /// @return The balance of the user
    function balanceOf(address user) external view returns (uint256) {
        return _balanceOf[user];
    }

    /// @notice Claims the gauge rewards for the user and updates the user's next claimable epoch
    /// @dev Will give a maximum of 50 epochs worth of rewards
    /// @return The amount of gauge rewards claimed
    function claim() external returns (uint256) {
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
                votingEscrow.epoch(
                    _workingBalanceHistory[msg.sender][0].timestamp
                ) +
                1;
        }
        // Iterate over a max of 50 epochs and/or user epochs
        uint256 amountToClaim;
        uint256 nextClaimableEpoch;
        for (uint256 i = 0; i < 50; i++) {
            nextClaimableEpoch = _userNextClaimableEpoch[msg.sender];

            // Break if the next claimable epoch is the one we are in
            if (nextClaimableEpoch >= votingEscrow.epoch(block.timestamp)) {
                break;
            } else {
                // Get the current user working Balance and its epoch
                DataTypes.WorkingBalance
                    memory workingBalance = _workingBalanceHistory[msg.sender][
                        _workingBalancePointer[msg.sender]
                    ];

                // Check if the user entire balance history has been iterated
                if (
                    _workingBalancePointer[msg.sender] ==
                    workingBalanceHistoryLength - 1
                ) {
                    if (_workingWeightHistory[nextClaimableEpoch] > 0) {
                        amountToClaim +=
                            (gaugeController.getGaugeRewards(
                                address(this),
                                nextClaimableEpoch
                            ) * workingBalance.weight) /
                            _workingWeightHistory[nextClaimableEpoch];
                    }

                    _userNextClaimableEpoch[msg.sender]++;
                } else {
                    // We haven't iterated over the entire user history
                    DataTypes.WorkingBalance
                        memory nextWorkingBalance = _workingBalanceHistory[
                            msg.sender
                        ][_workingBalancePointer[msg.sender] + 1];

                    // Check if the next working balance is in the same epoch as the current working balance
                    if (
                        votingEscrow.epoch(nextWorkingBalance.timestamp) ==
                        votingEscrow.epoch(workingBalance.timestamp)
                    ) {
                        _workingBalancePointer[msg.sender]++;
                    }
                    // Check if the next working balance is in the next claimable epoch
                    else if (
                        votingEscrow.epoch(nextWorkingBalance.timestamp) ==
                        nextClaimableEpoch
                    ) {
                        if (
                            _workingWeightHistory[nextClaimableEpoch] > 0 &&
                            workingBalance.amount <= nextWorkingBalance.amount
                        ) {
                            amountToClaim +=
                                (gaugeController.getGaugeRewards(
                                    address(this),
                                    nextClaimableEpoch
                                ) * workingBalance.weight) /
                                _workingWeightHistory[nextClaimableEpoch];
                        }
                        _workingBalancePointer[msg.sender]++;
                        _userNextClaimableEpoch[msg.sender]++;
                    } else {
                        // THe next working balance is not in the next claimable epoch
                        if (_workingWeightHistory[nextClaimableEpoch] > 0) {
                            amountToClaim +=
                                (gaugeController.getGaugeRewards(
                                    address(this),
                                    nextClaimableEpoch
                                ) * workingBalance.weight) /
                                _workingWeightHistory[nextClaimableEpoch];
                        }
                        _userNextClaimableEpoch[msg.sender]++;
                    }
                }
            }
        }

        INativeToken(_addressProvider.getNativeToken()).mintGaugeRewards(
            msg.sender,
            amountToClaim
        );

        return amountToClaim;
    }

    /// @notice Updates the total weight history by recording the current total weight for the current epoch and 128 previous epochs.
    /// @dev This function will break if it is not used for 128 epochs.
    function writeTotalWeightHistory() public {
        // Update last saved weight checkpoint and record weight for epochs
        // Will break if is not used for 128 epochs
        uint256 currentEpoch = IVotingEscrow(_addressProvider.getVotingEscrow())
            .epoch(block.timestamp);
        for (uint256 i = 0; i < 2 ** 7; i++) {
            //Increase epoch
            if (_workingWeightHistory.length >= currentEpoch) {
                break;
            }

            // Save epoch total weight
            _workingWeightHistory.push(_workingWeight);
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

        uint256 userVotingBalance = votingEscrow.userWeight(user);
        uint256 totalVotingSupply = votingEscrow.totalWeight();
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
                        totalSupply()) /
                    totalVotingSupply) / PercentageMath.PERCENTAGE_FACTOR
            );
        }

        DataTypes.WorkingBalance memory oldWorkingBalance;
        if (_workingBalanceHistory[user].length > 0) {
            oldWorkingBalance = _workingBalanceHistory[user][
                _workingBalanceHistory[user].length - 1
            ];
        }
        DataTypes.WorkingBalance memory newWorkingBalance = DataTypes
            .WorkingBalance({
                amount: _balanceOf[user],
                weight: newWeight,
                timestamp: block.timestamp
            });

        _workingWeight =
            _workingWeight +
            newWorkingBalance.amount -
            oldWorkingBalance.amount;

        _workingBalanceHistory[user].push(newWorkingBalance);
    }

    /// @notice Computes the boost of a user based on their working balance and their balance.
    /// @param user The address of the user.
    /// @return The boost of the user.
    function userBoost(address user) external view returns (uint256) {
        if (_balanceOf[user] == 0) {
            return 0;
        }
        return
            (2 *
                _workingBalanceHistory[user][
                    _workingBalanceHistory[user].length - 1
                ].amount *
                PercentageMath.PERCENTAGE_FACTOR) / _balanceOf[user];
    }

    /// @notice Updates the working balance of a user if their locked has expired.
    /// @param tokenId The tokenId of the user's locked balance.
    function kick(uint256 tokenId) external {
        address votingEscrowAddress = _addressProvider.getVotingEscrow();
        // Get user locked balance end time
        uint256 lockEnd = IVotingEscrow(votingEscrowAddress)
            .locked(tokenId)
            .end;

        if (lockEnd < block.timestamp) {
            _checkpoint(IERC721(votingEscrowAddress).ownerOf(tokenId));
        }
    }

    /// @notice Deposits LP tokens into the contract and updates the user's balance and working balance.
    /// @param amount The amount of LP tokens to deposit.
    function deposit(uint256 amount) external {
        require(amount > 0, "Deposit amount must be greater than 0");

        // Update balance
        _balanceOf[msg.sender] += amount;

        _checkpoint(msg.sender);

        IERC20(_lpToken).safeTransferFrom(msg.sender, address(this), amount);
    }

    /// @notice Withdraws LP tokens from the contract and updates the user's balance and working balance.
    /// @param amount The amount of LP tokens to withdraw.
    function withdraw(uint256 amount) external {
        require(
            amount <= _balanceOf[msg.sender],
            "Withdraw amount higher than balance"
        );

        // Update balance
        _balanceOf[msg.sender] -= amount;

        _checkpoint(msg.sender);

        IERC20(_lpToken).safeTransfer(msg.sender, amount);
    }
}
