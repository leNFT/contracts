// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.8.17;

import {IAddressesProvider} from "../../interfaces/IAddressesProvider.sol";
import {INativeToken} from "../../interfaces/INativeToken.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {DataTypes} from "../../libraries/types/DataTypes.sol";
import {IVotingEscrow} from "../../interfaces/IVotingEscrow.sol";
import {IGauge} from "../../interfaces/IGauge.sol";
import "hardhat/console.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {PercentageMath} from "../../libraries/math/PercentageMath.sol";

contract LendingGauge is IGauge {
    IAddressesProvider private _addressProvider;
    mapping(address => uint256) private _balanceOf;
    mapping(address => DataTypes.WorkingBalance[])
        private _workingBalanceHistory;
    mapping(address => uint256) private _workingBalancePointer;
    mapping(address => uint256) private _userNextClaimedEpoch;
    uint256 _workingSupply;
    uint256[] private _workingSupplyHistory;
    address private _lpToken;

    using SafeERC20 for IERC20;

    constructor(IAddressesProvider addressProvider, address lpToken_) {
        _addressProvider = addressProvider;
        _lpToken = lpToken_;
        _workingSupplyHistory = [0];
    }

    function lpToken() external view returns (address) {
        return _lpToken;
    }

    function totalSupply() public view returns (uint256) {
        return IERC20(_lpToken).balanceOf(address(this));
    }

    function workingSupply() external view returns (uint256) {
        return _workingSupply;
    }

    function balanceOf(address user) external view returns (uint256) {
        return _balanceOf[user];
    }

    function workingBalanceOf(address user) external view returns (uint256) {
        if (_workingBalanceHistory[user].length == 0) {
            return 0;
        }
        return
            _workingBalanceHistory[user][
                _workingBalanceHistory[user].length - 1
            ].amount;
    }

    function claim() external returns (uint256) {
        _checkpoint(msg.sender);

        IVotingEscrow votingEscrow = IVotingEscrow(
            _addressProvider.getVotingEscrow()
        );
        INativeToken nativeToken = INativeToken(
            _addressProvider.getNativeToken()
        );

        // Get maximum number of user epochs
        uint256 workingBalanceHistoryLength = _workingBalanceHistory[msg.sender]
            .length;
        // Check if user has any user actions and therefore something to claim
        if (workingBalanceHistoryLength == 0) {
            return 0;
        }

        // Set the next claimable epoch if it's the first time the user claims
        if (_userNextClaimedEpoch[msg.sender] == 0) {
            _userNextClaimedEpoch[msg.sender] =
                votingEscrow.epoch(
                    _workingBalanceHistory[msg.sender][0].timestamp
                ) +
                1;
        }

        // Iterate over a max of 50 weeks and/or user epochs
        uint256 amountToClaim;
        uint256 nextClaimedEpoch;
        for (uint256 i = 0; i < 50; i++) {
            nextClaimedEpoch = _userNextClaimedEpoch[msg.sender];
            console.log(
                "i = %s, nextClaimedEpoch = %s , votingEscrow.epoch(block.timestamp) = %s",
                i,
                nextClaimedEpoch,
                votingEscrow.epoch(block.timestamp)
            );
            // Break if the next claimable epoch is the one we are in
            if (nextClaimedEpoch >= votingEscrow.epoch(block.timestamp)) {
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
                    console.log(
                        "Claiming last working balance",
                        _workingBalancePointer[msg.sender]
                    );
                    amountToClaim +=
                        (nativeToken.getGaugeRewards(nextClaimedEpoch) *
                            workingBalance.amount) /
                        _workingSupplyHistory[nextClaimedEpoch];

                    _userNextClaimedEpoch[msg.sender]++;
                } else {
                    DataTypes.WorkingBalance
                        memory nextWorkingBalance = _workingBalanceHistory[
                            msg.sender
                        ][_workingBalancePointer[msg.sender] + 1];

                    if (
                        votingEscrow.epoch(nextWorkingBalance.timestamp) ==
                        votingEscrow.epoch(workingBalance.timestamp)
                    ) {
                        _workingBalancePointer[msg.sender]++;
                        console.log(
                            "Incremented working balance pointer",
                            _workingBalancePointer[msg.sender]
                        );
                    } else {
                        console.log(
                            "Claiming working balance %s with %s tokens out of %s",
                            nativeToken.getGaugeRewards(nextClaimedEpoch),
                            workingBalance.amount,
                            _workingSupplyHistory[nextClaimedEpoch]
                        );
                        if (_workingSupplyHistory[nextClaimedEpoch] != 0) {
                            amountToClaim +=
                                (nativeToken.getGaugeRewards(nextClaimedEpoch) *
                                    workingBalance.amount) /
                                _workingSupplyHistory[nextClaimedEpoch];
                        }
                        _userNextClaimedEpoch[msg.sender]++;
                        if (
                            votingEscrow.epoch(nextWorkingBalance.timestamp) ==
                            _userNextClaimedEpoch[msg.sender]
                        ) {
                            _workingBalancePointer[msg.sender]++;
                        }
                    }
                }
            }
        }

        console.log("amountToClaim", amountToClaim);
        INativeToken(_addressProvider.getNativeToken()).mintGaugeRewards(
            msg.sender,
            amountToClaim
        );

        return amountToClaim;
    }

    function writeTotalWeightHistory() public {
        // Update last saved weight checkpoint and record weight for epochs
        // Will break if is not used for 128 weeks
        uint256 currentEpoch = IVotingEscrow(_addressProvider.getVotingEscrow())
            .epoch(block.timestamp);
        for (uint256 i = 0; i < 2 ** 7; i++) {
            //Increase epoch
            if (currentEpoch > _workingSupplyHistory.length) {
                break;
            }

            // Save epoch total weight
            _workingSupplyHistory.push(_workingSupply);
        }
    }

    function _checkpoint(address user) internal {
        // Get user ve balance and total ve balance
        IVotingEscrow votingEscrow = IVotingEscrow(
            _addressProvider.getVotingEscrow()
        );

        uint256 userVotingBalance = votingEscrow.balanceOf(user);
        uint256 totalVotingSupply = votingEscrow.totalSupply();
        uint256 newAmount;

        if (totalVotingSupply == 0) {
            newAmount = _balanceOf[user];
        } else {
            newAmount = Math.min(
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
            .WorkingBalance({amount: newAmount, timestamp: block.timestamp});

        _workingSupply =
            _workingSupply +
            newWorkingBalance.amount -
            oldWorkingBalance.amount;
        writeTotalWeightHistory();

        _workingBalanceHistory[user].push(newWorkingBalance);
    }

    function userBoost(address user) external view returns (uint256) {
        if (_balanceOf[user] == 0) {
            return 0;
        }
        return
            (_workingBalanceHistory[user][
                _workingBalanceHistory[user].length - 1
            ].amount * PercentageMath.PERCENTAGE_FACTOR) / _balanceOf[user];
    }

    function kick(address user) external {
        // Get user locked balance end time
        uint256 lockEnd = IVotingEscrow(_addressProvider.getVotingEscrow())
            .locked(user)
            .end;

        if (lockEnd < block.timestamp) {
            _checkpoint(user);
        }
    }

    function deposit(uint256 amount) external {
        // Update balance
        _balanceOf[msg.sender] += amount;

        _checkpoint(msg.sender);

        IERC20(_lpToken).safeTransferFrom(msg.sender, address(this), amount);
    }

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
