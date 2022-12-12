// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.8.17;

import {IAddressesProvider} from "../interfaces/IAddressesProvider.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {DataTypes} from "../libraries/types/DataTypes.sol";
import {IVotingEscrow} from "../interfaces/IVotingEscrow.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {PercentageMath} from "../libraries/math/PercentageMath.sol";

contract LiquidityGauge {
    IAddressesProvider private _addressProvider;
    mapping(address => uint256) private _balanceOf;
    mapping(address => DataTypes.WorkingBalance[])
        private _workingBalanceHistory;
    mapping(address => uint256) private _workingBalancePointer;
    mapping(address => uint256) private _userClaimedEpoch;
    uint256 _workingSupply;
    uint256[] private _workingSupplyHistory;
    address private _lpToken;

    using SafeERC20 for IERC20;

    constructor(IAddressesProvider addressProvider, address lpToken_) {
        _addressProvider = addressProvider;
        _lpToken = lpToken_;
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

    function balanceOf() external view returns (uint256) {
        return _balanceOf[msg.sender];
    }

    function workingBalance() external view returns (uint256) {
        if (_workingBalanceHistory[msg.sender].length == 0) {
            return 0;
        }
        return
            _workingBalanceHistory[msg.sender][
                _workingBalanceHistory[msg.sender].length - 1
            ].amount;
    }

    function claim() external returns (uint256) {
        _checkpoint(msg.sender);

        IVotingEscrow votingEscrow = IVotingEscrow(
            _addressProvider.getVotingEscrow()
        );

        // Get maximum number of user epochs
        uint256 currentEpoch = votingEscrow.epoch(block.timestamp);
        uint256 workingBalanceHistoryLength = _workingBalanceHistory[msg.sender]
            .length;
        // Check if user has any user actions and therefore something to claim
        if (workingBalanceHistoryLength == 0) {
            return 0;
        }

        uint256 workingBalanceEpoch = votingEscrow.epoch(
            _workingBalanceHistory[msg.sender][
                _workingBalancePointer[msg.sender]
            ].timestamp
        );

        // Iterate over a max of 50 weeks and/or user epochs
        uint256 amountToClaim;
        for (uint256 i = 0; i < 50; i++) {
            if (_userClaimedEpoch[msg.sender] == currentEpoch - 1) {
                break;
            } else {
                if (
                    _workingBalancePointer[msg.sender] ==
                    workingBalanceHistoryLength - 1
                ) {
                    amountToClaim += 0;

                    _userClaimedEpoch[msg.sender]++;
                } else {
                    uint256 nextWorkingBalanceEpoch = votingEscrow.epoch(
                        _workingBalanceHistory[msg.sender][
                            _workingBalancePointer[msg.sender] + 1
                        ].timestamp
                    );

                    if (nextWorkingBalanceEpoch == workingBalanceEpoch) {
                        _workingBalancePointer[msg.sender]++;
                    } else {
                        amountToClaim += 0;

                        _userClaimedEpoch[msg.sender] = nextWorkingBalanceEpoch;
                        if (
                            nextWorkingBalanceEpoch ==
                            _userClaimedEpoch[msg.sender] + 1
                        ) {
                            _workingBalancePointer[msg.sender]++;
                        }
                    }
                }
            }
        }

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
        writeTotalWeightHistory();

        // Get user ve balance and total ve balance
        IVotingEscrow votingEscrow = IVotingEscrow(
            _addressProvider.getVotingEscrow()
        );

        uint256 userVotingBalance = votingEscrow.balanceOf(user);
        uint256 totalVotingSupply = votingEscrow.totalSupply();

        DataTypes.WorkingBalance memory newWorkingBalance = DataTypes
            .WorkingBalance({
                amount: Math.min(
                    _balanceOf[msg.sender],
                    (PercentageMath.HALF_PERCENTAGE_FACTOR *
                        _balanceOf[msg.sender] +
                        (PercentageMath.HALF_PERCENTAGE_FACTOR *
                            userVotingBalance *
                            totalSupply()) /
                        totalVotingSupply) / PercentageMath.PERCENTAGE_FACTOR
                ),
                timestamp: block.timestamp
            });

        _workingBalanceHistory[msg.sender].push(newWorkingBalance);
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
