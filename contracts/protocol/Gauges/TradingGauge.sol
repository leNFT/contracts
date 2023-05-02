// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.8.19;

import {IAddressesProvider} from "../../interfaces/IAddressesProvider.sol";
import {INativeToken} from "../../interfaces/INativeToken.sol";
import {IGaugeController} from "../../interfaces/IGaugeController.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {DataTypes} from "../../libraries/types/DataTypes.sol";
import {IVotingEscrow} from "../../interfaces/IVotingEscrow.sol";
import {ITradingPool} from "../../interfaces/ITradingPool.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {PercentageMath} from "../../libraries/math/PercentageMath.sol";
import {DataTypes} from "../../libraries/types/DataTypes.sol";
import {IGauge} from "../../interfaces/IGauge.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {ERC721Holder} from "@openzeppelin/contracts/token/ERC721/utils/ERC721Holder.sol";
import "hardhat/console.sol";

/// @title Trading Gauge Contract
/// @notice A contract for managing the distribution of rewards to Trading LPs
contract TradingGauge is IGauge, ERC721Holder {
    uint256 public constant LP_MATURITY_PERIOD = 6; // 6 epochs
    IAddressesProvider private _addressProvider;
    mapping(uint256 => address) private _ownerOf;
    mapping(address => uint256) private _balanceOf;
    uint256 private _totalSupply;
    mapping(address => mapping(uint256 => uint256)) private _ownedTokens;
    mapping(uint256 => uint256) private _ownedTokensIndex;
    mapping(address => DataTypes.WorkingBalance[])
        private _workingBalanceHistory;
    mapping(address => uint256) private _workingBalancePointer;
    mapping(address => uint256) private _userNextClaimableEpoch;
    uint256 private _workingWeight;
    uint256[] private _workingWeightHistory;
    address private _lpToken;
    mapping(uint256 => uint256) private _lpValue;
    mapping(address => uint256) private _userLPValue;
    uint256 private _totalLPValue;

    using SafeERC20 for IERC20;

    event DepositLP(address indexed user, uint256 lpId);
    event WithdrawLP(address indexed user, uint256 lpId);

    constructor(IAddressesProvider addressProvider, address lpToken_) {
        _addressProvider = addressProvider;
        _lpToken = lpToken_;
        _workingWeightHistory = [0];
    }

    /// @notice Returns the address of the LP token supported by the gauge
    /// @return The address of the LP token
    function lpToken() external view returns (address) {
        return _lpToken;
    }

    /// @notice Calculates and returns the amount of rewards a user can claim and updates user's working balance history
    /// @dev Will give a maximum of 50 epochs worth of rewards
    /// @return The amount of rewards the user can claim
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
                        _userNextClaimableEpoch[msg.sender]++;
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

    /// @notice Updates the total weight history for the contract and records the total weight for epochs.
    /// @dev This function will break if it is not used for 128 epochs.
    function writeTotalWeightHistory() public {
        // Update last saved weight checkpoint and record weight for epochs
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

    /// @notice Gets the maturity boost for a given time interval since inception
    /// @param timeInterval The time interval to get the boost for.
    /// @return The maturity boost.
    function _maturityMultiplier(
        uint256 timeInterval
    ) internal view returns (uint256) {
        uint256 lpMaturity = LP_MATURITY_PERIOD *
            IVotingEscrow(_addressProvider.getVotingEscrow()).epochPeriod();
        if (timeInterval > lpMaturity) {
            return PercentageMath.PERCENTAGE_FACTOR;
        } else {
            return
                (PercentageMath.PERCENTAGE_FACTOR * timeInterval) / lpMaturity;
        }
    }

    /// @notice Updates the working balance and total supply for a user.
    /// @param user The address of the user whose working balance needs to be updated.
    function _checkpoint(address user) internal {
        // Get user ve balance and total ve balance
        IVotingEscrow votingEscrow = IVotingEscrow(
            _addressProvider.getVotingEscrow()
        );

        // Make sure the voting escrow's total supply is up to date
        votingEscrow.writeTotalWeightHistory();

        uint256 userVotingBalance = votingEscrow.userWeight(user);
        uint256 totalVotingSupply = votingEscrow.totalWeight();
        uint256 newWeight;

        writeTotalWeightHistory();

        if (totalVotingSupply == 0) {
            newWeight = _userLPValue[user];
        } else {
            newWeight = Math.min(
                _userLPValue[user],
                (PercentageMath.HALF_PERCENTAGE_FACTOR *
                    _userLPValue[user] +
                    (PercentageMath.HALF_PERCENTAGE_FACTOR *
                        userVotingBalance *
                        _totalLPValue) /
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
                amount: _userLPValue[user],
                weight: newWeight,
                timestamp: block.timestamp
            });

        // Update global working supply and working balance history if there were any changes
        _workingWeight =
            _workingWeight +
            newWorkingBalance.weight -
            oldWorkingBalance.weight;

        _workingBalanceHistory[user].push(newWorkingBalance);
    }

    /// @notice Triggers a checkpoint for a user if their locked balance has ended.
    /// @param tokenId The ID of token
    function kick(uint256 tokenId) external {
        address votingEscrowAddress = _addressProvider.getVotingEscrow();
        // Get user locked balance end time
        if (
            IVotingEscrow(votingEscrowAddress).locked(tokenId).end <
            block.timestamp
        ) {
            _checkpoint(IERC721(votingEscrowAddress).ownerOf(tokenId));
        }
    }

    /// @notice Deposits LP tokens to the contract, updates balances and working balances for the user.
    /// @param lpId The ID of the LP token being deposited.
    function deposit(uint256 lpId) external {
        DataTypes.LiquidityPair memory lp = ITradingPool(_lpToken).getLP(lpId);

        // Only Trade type LPs can be staked
        require(
            lp.lpType == DataTypes.LPType.Trade ||
                lp.lpType == DataTypes.LPType.TradeDown ||
                lp.lpType == DataTypes.LPType.TradeUp,
            "Only Trade LPs can be staked"
        );

        // Add token value
        uint256 depositLpValue = calculateLpValue(
            lp.nftIds.length,
            lp.tokenAmount,
            lp.spotPrice
        );

        // LP value must be greater than 0
        require(depositLpValue > 0, "LP value must be greater than 0");

        _ownerOf[lpId] = msg.sender;
        _lpValue[lpId] = depositLpValue;
        _userLPValue[msg.sender] += depositLpValue;
        _totalLPValue += depositLpValue;

        _checkpoint(msg.sender);

        IERC721(_lpToken).safeTransferFrom(msg.sender, address(this), lpId);

        uint256 lastTokenIndex = _balanceOf[msg.sender];
        _ownedTokens[msg.sender][lastTokenIndex] = lpId;
        _ownedTokensIndex[lpId] = lastTokenIndex;
        _balanceOf[msg.sender] += 1;
        _totalSupply += 1;

        emit DepositLP(msg.sender, lpId);
    }

    /// @notice Allows the owner of a liquidity position to withdraw it and receive their tokens back.
    /// @param lpId The ID of the liquidity position to be withdrawn.
    function withdraw(uint256 lpId) public {
        require(
            _ownerOf[lpId] == msg.sender,
            "Not the owner of liquidity position"
        );

        // remove token value
        _userLPValue[msg.sender] -= _lpValue[lpId];
        _totalLPValue -= _lpValue[lpId];

        // Update balance
        delete _ownerOf[lpId];
        delete _lpValue[lpId];

        _checkpoint(msg.sender);

        IERC721(_lpToken).safeTransferFrom(address(this), msg.sender, lpId);

        uint256 lastTokenIndex = _balanceOf[msg.sender] - 1;
        uint256 tokenIndex = _ownedTokensIndex[lpId];

        // When the token to delete is the last token, the swap operation is unnecessary
        if (tokenIndex != lastTokenIndex) {
            uint256 lastTokenId = _ownedTokens[msg.sender][lastTokenIndex];

            _ownedTokens[msg.sender][tokenIndex] = lastTokenId; // Move the last token to the slot of the to-delete token
            _ownedTokensIndex[lastTokenId] = tokenIndex; // Update the moved token's index
        }

        // This also deletes the contents at the last position of the array
        delete _ownedTokensIndex[lpId];
        delete _ownedTokens[msg.sender][lastTokenIndex];

        _balanceOf[msg.sender] -= 1;
        _totalSupply -= 1;

        emit WithdrawLP(msg.sender, lpId);
    }

    /// @notice Allows a user to withdraw multiple liquidity positions at once.
    /// @param lpIds An array of IDs of the liquidity positions to be withdrawn.
    function withdrawBatch(uint256[] calldata lpIds) external {
        for (uint256 i = 0; i < lpIds.length; i++) {
            withdraw(lpIds[i]);
        }
    }

    /// @notice Returns the value of a user's liquidity positions.
    /// @param user The address of the user whose liquidity positions will be valued.
    /// @return The total value of the user's liquidity positions.
    function userLPValue(address user) external view returns (uint256) {
        return _userLPValue[user];
    }

    /// @notice Returns the total value of all liquidity positions in the contract.
    /// @return The total value of all liquidity positions.
    function totalLPValue() external view returns (uint256) {
        return _totalLPValue;
    }

    /// @notice Returns the boost multiplier for a user's liquidity positions.
    /// @param user The address of the user whose boost multiplier will be returned.
    /// @return The boost multiplier for the user's liquidity positions.
    function userBoost(address user) external view returns (uint256) {
        if (_userLPValue[user] == 0) {
            return 0;
        }
        return
            (2 *
                _workingBalanceHistory[user][
                    _workingBalanceHistory[user].length - 1
                ].amount *
                PercentageMath.PERCENTAGE_FACTOR) / _userLPValue[user];
    }

    /// @notice Returns the current maturity boost for a user
    /// @param user The address of the user whose maturity boost will be returned.
    /// @return The current maturity boost for the user.
    function userMaturityMultiplier(
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

    /// @notice Returns the ID of the liquidity position at the specified index in a user's list of liquidity positions.
    /// @param user The address of the user whose list of liquidity positions will be accessed.
    /// @param index The index of the liquidity position to be returned.
    /// @return The ID of the liquidity position at the specified index.
    function lpOfOwnerByIndex(
        address user,
        uint256 index
    ) external view returns (uint256) {
        return _ownedTokens[user][index];
    }

    /// @notice Retrieves the number of staked liquidity positions a user has staked.
    /// @param user Address of the account to retrieve balance from.
    /// @return Returns the balance of the specified address.
    function balanceOf(address user) external view returns (uint256) {
        return _balanceOf[user];
    }

    /// @notice Retrieves the total supply of staked LP's.
    /// @return Returns the total supply of staked LP's.
    function totalSupply() external view returns (uint256) {
        return _totalSupply;
    }

    /// @notice Calculates the total value of a liquidity pair.
    /// @param nftAmount Amount of NFTs for the LP
    /// @param tokenAmount Amount of tokens in the LP
    /// @param spotPrice Spot price of the LP
    /// @return Returns the calculated value of the liquidity pair.
    function calculateLpValue(
        uint256 nftAmount,
        uint256 tokenAmount,
        uint256 spotPrice
    ) public pure returns (uint256) {
        uint256 nftsAppraisal = nftAmount * spotPrice;
        uint256 validTokenAmount = tokenAmount >= spotPrice ? tokenAmount : 0;

        // Value is higher if the lp is in equilibrium
        return
            nftsAppraisal > validTokenAmount ? validTokenAmount : nftsAppraisal;
    }
}
