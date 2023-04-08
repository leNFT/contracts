// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.8.19;

import {IAddressesProvider} from "../../interfaces/IAddressesProvider.sol";
import {INativeToken} from "../../interfaces/INativeToken.sol";
import {IGaugeController} from "../../interfaces/IGaugeController.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
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
import {IERC721Receiver} from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import "hardhat/console.sol";

/// @title Trading Gauge Contract
/// @notice A contract for managing the distribution of rewards to Ttrading LPs
contract TradingGauge is IGauge, IERC721Receiver {
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
    uint256 private _workingSupply;
    uint256[] private _workingSupplyHistory;
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
        _workingSupplyHistory = [0];
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
        uint256 nextClaimedEpoch;
        for (uint256 i = 0; i < 50; i++) {
            nextClaimedEpoch = _userNextClaimableEpoch[msg.sender];
            console.log("nextClaimedEpoch", nextClaimedEpoch);

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
                    if (_workingSupplyHistory[nextClaimedEpoch] > 0) {
                        amountToClaim +=
                            (gaugeController.getGaugeRewards(
                                address(this),
                                nextClaimedEpoch
                            ) * workingBalance.amount) /
                            _workingSupplyHistory[nextClaimedEpoch];
                    }

                    _userNextClaimableEpoch[msg.sender]++;
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
                    } else {
                        if (_workingSupplyHistory[nextClaimedEpoch] > 0) {
                            amountToClaim +=
                                (gaugeController.getGaugeRewards(
                                    address(this),
                                    nextClaimedEpoch
                                ) * workingBalance.amount) /
                                _workingSupplyHistory[nextClaimedEpoch];
                        }
                        _userNextClaimableEpoch[msg.sender]++;
                        if (
                            votingEscrow.epoch(nextWorkingBalance.timestamp) +
                                1 ==
                            _userNextClaimableEpoch[msg.sender]
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

    /// @notice Updates the total weight history for the contract and records the total weight for epochs.
    /// @dev This function will break if it is not used for 128 epochs.
    function writeTotalWeightHistory() public {
        // Update last saved weight checkpoint and record weight for epochs
        uint256 currentEpoch = IVotingEscrow(_addressProvider.getVotingEscrow())
            .epoch(block.timestamp);
        for (uint256 i = 0; i < 2 ** 7; i++) {
            //Increase epoch
            if (_workingSupplyHistory.length >= currentEpoch) {
                break;
            }

            // Save epoch total weight
            _workingSupplyHistory.push(_workingSupply);
        }
    }

    /// @notice Updates the working balance and total supply for a user.
    /// @param user The address of the user whose working balance needs to be updated.
    function _checkpoint(address user) internal {
        // Get user ve balance and total ve balance
        address votingEscrow = _addressProvider.getVotingEscrow();

        // Make sure the voting escrow's total supply is up to date
        IVotingEscrow(votingEscrow).writeTotalWeightHistory();

        uint256 userVotingBalance = IERC20(votingEscrow).balanceOf(user);
        uint256 totalVotingSupply = IERC20(votingEscrow).totalSupply();
        uint256 newAmount;

        writeTotalWeightHistory();

        if (totalVotingSupply == 0) {
            newAmount = _userLPValue[user];
        } else {
            newAmount = Math.min(
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
            .WorkingBalance({amount: newAmount, timestamp: block.timestamp});

        _workingSupply =
            _workingSupply +
            newWorkingBalance.amount -
            oldWorkingBalance.amount;

        _workingBalanceHistory[user].push(newWorkingBalance);
    }

    /// @notice Triggers a checkpoint for a user if their locked balance has ended.
    /// @param user The address of the user whose locked balance needs to be checked.
    function kick(address user) external {
        // Get user locked balance end time
        if (
            IVotingEscrow(_addressProvider.getVotingEscrow()).locked(user).end <
            block.timestamp
        ) {
            _checkpoint(user);
        }
    }

    /// @notice Deposits LP tokens to the contract, updates balances and working balances for the user.
    /// @param lpId The ID of the LP token being deposited.
    function deposit(uint256 lpId) external {
        DataTypes.LiquidityPair memory lp = ITradingPool(_lpToken).getLP(lpId);

        // Only Trade type LPs can be staked
        require(
            lp.lpType == DataTypes.LPType.Trade,
            "Only Trade LPs can be staked"
        );

        // Update owner
        _ownerOf[lpId] = msg.sender;

        // Add token value
        uint256 depositLpValue = calculateLpValue(
            lp.nftAmount,
            lp.tokenAmount,
            lp.spotPrice
        );
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
    ) public view returns (uint256) {
        uint256 nftsAppraisal = nftAmount * spotPrice;
        uint256 validTokenAmount = tokenAmount > spotPrice ? tokenAmount : 0;

        // Value is higher if the lp is in equilibrium
        return
            nftsAppraisal > validTokenAmount ? validTokenAmount : nftsAppraisal;
    }

    function onERC721Received(
        address,
        address,
        uint256,
        bytes calldata
    ) public pure override returns (bytes4) {
        return
            bytes4(
                keccak256("onERC721Received(address,address,uint256,bytes)")
            );
    }
}
