// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.8.17;

import {IAddressesProvider} from "../../interfaces/IAddressesProvider.sol";
import {INativeToken} from "../../interfaces/INativeToken.sol";
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

contract TradingGauge is IGauge, IERC721Receiver {
    IAddressesProvider private _addressProvider;
    mapping(uint256 => address) private _ownerOf;
    mapping(address => uint256) private _balanceOf;
    mapping(address => mapping(uint256 => uint256)) private _ownedTokens;
    mapping(uint256 => uint256) private _ownedTokensIndex;
    mapping(address => DataTypes.WorkingBalance[])
        private _workingBalanceHistory;
    mapping(address => uint256) private _workingBalancePointer;
    mapping(address => uint256) private _userClaimedEpoch;
    uint256 private _workingSupply;
    uint256[] private _workingSupplyHistory;
    address private _lpToken;
    mapping(uint256 => uint256) private _lpValue;
    mapping(address => uint256) private _userLPValue;
    uint256 private _totalLPValue;

    using SafeERC20 for IERC20;

    event DepositLP(address user, uint256 lpId);
    event WithdrawLP(address user, uint256 lpId);

    constructor(IAddressesProvider addressProvider, address lpToken_) {
        _addressProvider = addressProvider;
        _lpToken = lpToken_;
    }

    function lpToken() external view returns (address) {
        return _lpToken;
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
        uint256 currentEpoch = votingEscrow.epoch(block.timestamp);
        uint256 workingBalanceHistoryLength = _workingBalanceHistory[msg.sender]
            .length;
        // Check if user has any user actions and therefore something to claim
        if (workingBalanceHistoryLength == 0) {
            return 0;
        }

        // Iterate over a max of 50 weeks and/or user epochs
        uint256 amountToClaim;
        for (uint256 i = 0; i < 50; i++) {
            if (_userClaimedEpoch[msg.sender] == currentEpoch - 1) {
                break;
            } else {
                DataTypes.WorkingBalance
                    memory workingBalance = _workingBalanceHistory[msg.sender][
                        _workingBalancePointer[msg.sender]
                    ];
                uint256 workingBalanceEpoch = votingEscrow.epoch(
                    workingBalance.timestamp
                );

                if (
                    _workingBalancePointer[msg.sender] ==
                    workingBalanceHistoryLength - 1
                ) {
                    amountToClaim +=
                        (nativeToken.getEpochGaugeRewards(workingBalanceEpoch) *
                            workingBalance.amount) /
                        _workingSupplyHistory[workingBalanceEpoch];

                    _userClaimedEpoch[msg.sender]++;
                } else {
                    DataTypes.WorkingBalance
                        memory nextWorkingBalance = _workingBalanceHistory[
                            msg.sender
                        ][_workingBalancePointer[msg.sender] + 1];
                    uint256 nextWorkingBalanceEpoch = votingEscrow.epoch(
                        nextWorkingBalance.timestamp
                    );

                    if (nextWorkingBalanceEpoch == workingBalanceEpoch) {
                        _workingBalancePointer[msg.sender]++;
                    } else {
                        amountToClaim +=
                            (nativeToken.getEpochGaugeRewards(
                                nextWorkingBalanceEpoch
                            ) * workingBalance.amount) /
                            _workingSupplyHistory[workingBalanceEpoch];

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
        // Get user ve balance and total ve balance
        IVotingEscrow votingEscrow = IVotingEscrow(
            _addressProvider.getVotingEscrow()
        );

        uint256 userVotingBalance = votingEscrow.balanceOf(user);
        uint256 totalVotingSupply = votingEscrow.totalSupply();
        uint256 newAmount;

        if (totalVotingSupply == 0) {
            newAmount = _userLPValue[msg.sender];
        } else {
            newAmount = Math.min(
                _userLPValue[msg.sender],
                (PercentageMath.HALF_PERCENTAGE_FACTOR *
                    _userLPValue[msg.sender] +
                    (PercentageMath.HALF_PERCENTAGE_FACTOR *
                        userVotingBalance *
                        _totalLPValue) /
                    totalVotingSupply) / PercentageMath.PERCENTAGE_FACTOR
            );
        }
        DataTypes.WorkingBalance memory oldWorkingBalance;
        if (_workingBalanceHistory[msg.sender].length > 0) {
            oldWorkingBalance = _workingBalanceHistory[msg.sender][
                _workingBalanceHistory[msg.sender].length - 1
            ];
        }
        DataTypes.WorkingBalance memory newWorkingBalance = DataTypes
            .WorkingBalance({amount: newAmount, timestamp: block.timestamp});

        _workingSupply += newWorkingBalance.amount - oldWorkingBalance.amount;
        writeTotalWeightHistory();
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

    function deposit(uint256 lpId) external {
        // Update owner
        _ownerOf[lpId] = msg.sender;

        // Add token value
        uint256 depositLpValue = lpValue(lpId);
        _lpValue[lpId] = depositLpValue;
        _userLPValue[msg.sender] += depositLpValue;
        _totalLPValue += depositLpValue;

        _checkpoint(msg.sender);

        IERC721(_lpToken).safeTransferFrom(msg.sender, address(this), lpId);

        uint256 lastTokenIndex = _balanceOf[msg.sender];
        _ownedTokens[msg.sender][lastTokenIndex] = lpId;
        _ownedTokensIndex[lpId] = lastTokenIndex;
        _balanceOf[msg.sender] += 1;

        emit DepositLP(msg.sender, lpId);
    }

    function withdraw(uint256 lpId) external {
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

        emit WithdrawLP(msg.sender, lpId);
    }

    function userLPValue(address user) external view returns (uint256) {
        return _userLPValue[user];
    }

    function userBoost(address user) external view returns (uint256) {
        if (_userLPValue[user] == 0) {
            return 0;
        }
        return
            (_workingBalanceHistory[user][
                _workingBalanceHistory[user].length - 1
            ].amount * PercentageMath.PERCENTAGE_FACTOR) / _userLPValue[user];
    }

    function lpOfOwnerByIndex(
        address user,
        uint256 index
    ) external view returns (uint256) {
        return _ownedTokens[user][index];
    }

    function balanceOf(address user) external view returns (uint256) {
        return _balanceOf[user];
    }

    function lpValue(uint256 lpId) public view returns (uint256) {
        DataTypes.LiquidityPair memory lp = ITradingPool(_lpToken).getLP(lpId);

        uint256 nftsAppraisal = lp.nftIds.length * lp.price;
        uint256 returnValue = 0;

        // Value is higher if the lp is in equilibrium
        if (nftsAppraisal > lp.tokenAmount) {
            returnValue = lp.tokenAmount;
        } else {
            returnValue = nftsAppraisal;
        }

        return returnValue;
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
