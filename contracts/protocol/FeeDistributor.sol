// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.8.17;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {IAddressesProvider} from "../interfaces/IAddressesProvider.sol";
import {IFeeDistributor} from "../interfaces/IFeeDistributor.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {ContextUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ContextUpgradeable.sol";
import {IVotingEscrow} from "../interfaces/IVotingEscrow.sol";
import {SafeERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import {IERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import {Time} from "../libraries/Time.sol";
import {DataTypes} from "../libraries/types/DataTypes.sol";

contract FeeDistributor is
    Initializable,
    ContextUpgradeable,
    OwnableUpgradeable,
    IFeeDistributor
{
    IAddressesProvider private _addressProvider;
    mapping(address => mapping(address => uint256)) private _userHistoryPointer;
    mapping(address => mapping(uint256 => uint256)) private _epochFees;
    mapping(address => mapping(address => uint256)) private _userClaimedEpoch;

    using SafeERC20Upgradeable for IERC20Upgradeable;

    modifier onlyMarket() {
        require(
            _msgSender() == _addressProvider.getLendingMarket(),
            "Caller must be Market contract"
        );
        _;
    }

    function initialize(
        IAddressesProvider addressProvider
    ) external initializer {
        __Ownable_init();
        _addressProvider = addressProvider;
    }

    function addFeesToEpoch(address token, uint256 amount) external onlyMarket {
        // Find epoch we're in
        uint256 epoch = IVotingEscrow(_addressProvider.getVotingEscrow()).epoch(
            block.timestamp
        );
        // Add fees to current epoch
        _epochFees[token][epoch] += amount;
    }

    function claim(address token) external override returns (uint256) {
        IVotingEscrow votingEscrow = IVotingEscrow(
            _addressProvider.getVotingEscrow()
        );

        // Check if user has any user actions and therefore something to claim
        if (votingEscrow.userHistoryLength(msg.sender) == 0) {
            return 0;
        }

        // Iterate over a max of 50 weeks and/or user epochs
        uint256 amountToClaim;
        DataTypes.Point memory userHistoryPoint;
        uint256 nextClaimedEpoch;
        uint256 nextClaimedEpochTimestamp;
        uint256 nextPointEpoch;
        for (uint i = 0; i < 50; i++) {
            if (
                _userClaimedEpoch[token][msg.sender] ==
                votingEscrow.epoch(block.timestamp) - 1
            ) {
                break;
            } else {
                userHistoryPoint = votingEscrow.getUserHistoryPoint(
                    msg.sender,
                    _userHistoryPointer[token][msg.sender]
                );

                nextClaimedEpoch = _userClaimedEpoch[token][msg.sender] + 1;
                nextClaimedEpochTimestamp = votingEscrow.epochTimestamp(
                    _userClaimedEpoch[token][msg.sender] + 1
                );

                // Sum claimable amount if its the last activity in this epoch or the next activity is for a future epoch
                if (
                    _userHistoryPointer[token][msg.sender] ==
                    votingEscrow.userHistoryLength(msg.sender) - 1
                ) {
                    amountToClaim +=
                        (_epochFees[token][nextClaimedEpoch] *
                            (userHistoryPoint.bias -
                                userHistoryPoint.slope *
                                (nextClaimedEpochTimestamp -
                                    userHistoryPoint.timestamp))) /
                        votingEscrow.totalSupplyAt(nextClaimedEpoch);

                    _userClaimedEpoch[token][msg.sender] = nextClaimedEpoch;
                } else {
                    nextPointEpoch = votingEscrow.epoch(
                        votingEscrow
                            .getUserHistoryPoint(
                                msg.sender,
                                _userHistoryPointer[token][msg.sender]
                            )
                            .timestamp
                    );

                    if (
                        nextPointEpoch ==
                        votingEscrow.epoch(userHistoryPoint.timestamp)
                    ) {
                        _userHistoryPointer[token][msg.sender]++;
                    } else {
                        amountToClaim +=
                            (_epochFees[token][nextClaimedEpoch] *
                                (userHistoryPoint.bias -
                                    userHistoryPoint.slope *
                                    (nextClaimedEpochTimestamp -
                                        userHistoryPoint.timestamp))) /
                            votingEscrow.totalSupplyAt(nextClaimedEpoch);

                        _userClaimedEpoch[token][msg.sender] = nextClaimedEpoch;
                        if (nextPointEpoch == nextClaimedEpoch) {
                            _userHistoryPointer[token][msg.sender]++;
                        }
                    }
                }
            }
        }

        IERC20Upgradeable(token).safeTransfer(_msgSender(), amountToClaim);

        return amountToClaim;
    }
}
