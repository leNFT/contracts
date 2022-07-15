// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.8.15;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {ERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {IMarketAddressesProvider} from "../interfaces/IMarketAddressesProvider.sol";
import {INativeTokenVault} from "../interfaces/INativeTokenVault.sol";
import {INativeToken} from "../interfaces/INativeToken.sol";
import {ILoanCenter} from "../interfaces/ILoanCenter.sol";
import {INFTOracle} from "../interfaces/INFTOracle.sol";
import {ITokenOracle} from "../interfaces/ITokenOracle.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {SafeERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import {IERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import {ValidationLogic} from "../libraries/logic/ValidationLogic.sol";
import {RemoveVoteRequestLogic} from "../libraries/logic/RemoveVoteRequestLogic.sol";
import {DataTypes} from "../libraries/types/DataTypes.sol";
import {PercentageMath} from "../libraries/math/PercentageMath.sol";

contract NativeTokenVault is
    Initializable,
    ERC20Upgradeable,
    INativeTokenVault,
    OwnableUpgradeable
{
    uint256 internal constant boostMultiplier = 10;
    IMarketAddressesProvider internal _addressProvider;
    address internal _nativeToken;
    // User + collection to votes
    mapping(address => mapping(address => uint256)) private _votes;
    // User to votes
    mapping(address => uint256) private _freeVotes;
    //Collections to votes
    mapping(address => uint256) private _collectionVotes;
    //User + collection address to unlock requests
    mapping(address => mapping(address => DataTypes.RemoveVoteRequest))
        private _removeVoteRequests;

    using SafeERC20Upgradeable for IERC20Upgradeable;
    using RemoveVoteRequestLogic for DataTypes.RemoveVoteRequest;

    modifier onlyMarket() {
        require(
            _msgSender() == address(_addressProvider.getMarketAddress()),
            "Caller must be Market contract"
        );
        _;
    }

    function initialize(
        IMarketAddressesProvider addressProvider,
        address nativeToken,
        string calldata name,
        string calldata symbol
    ) external initializer {
        __Ownable_init();
        __ERC20_init(name, symbol);
        _addressProvider = addressProvider;
        _nativeToken = nativeToken;
    }

    function deposit(uint256 amount) external {
        ValidationLogic.validateNativeTokenDeposit(_nativeToken, amount);

        // Find how many tokens the reserve should mint
        uint256 veTokenAmount;
        if (totalSupply() == 0) {
            veTokenAmount = amount;
        } else {
            veTokenAmount = (amount * totalSupply()) / _getLockedBalance();
        }

        // Send native token from depositor to the vault
        IERC20Upgradeable(_nativeToken).safeTransferFrom(
            msg.sender,
            address(this),
            amount
        );

        //Mint veToken (locked) tokens
        _mint(msg.sender, veTokenAmount);

        //Update the number of unused votes
        _freeVotes[msg.sender] += veTokenAmount;
    }

    function withdraw(uint256 amount) external {
        ValidationLogic.validateNativeTokenWithdraw(_addressProvider, amount);

        // Find how many tokens the reserve should mint
        uint256 veTokenAmount;
        if (totalSupply() == 0) {
            veTokenAmount = amount;
        } else {
            veTokenAmount = (amount * totalSupply()) / _getLockedBalance();
        }

        // Burn the veToken
        _burn(msg.sender, amount);

        //Update the number of unused votes
        _freeVotes[msg.sender] -= veTokenAmount;

        // Withdraw the native token from the vault
        IERC20Upgradeable(_nativeToken).safeTransferFrom(
            address(this),
            msg.sender,
            amount
        );
    }

    function vote(uint256 amount, address collection) external {
        ValidationLogic.validateVote(_addressProvider, amount, collection);

        // Vote for a collection with the tokens we just minted
        _votes[msg.sender][collection] += amount;
        _collectionVotes[collection] += amount;

        _freeVotes[msg.sender] -= amount;
    }

    function createRemoveVoteRequest(uint256 amount, address collection)
        external
    {
        //Create rquest and add it to the list
        _removeVoteRequests[msg.sender][collection].init(msg.sender, amount);
    }

    function removeVote(uint256 amount, address collection) external {
        ValidationLogic.validateRemoveVote(
            _addressProvider,
            amount,
            collection
        );

        // Vote for a collection with the tokens we just minted
        _votes[msg.sender][collection] -= amount;
        _collectionVotes[collection] -= amount;

        _freeVotes[msg.sender] += amount;
    }

    function getRemoveVoteRequest(address user, address collection)
        external
        view
        returns (DataTypes.RemoveVoteRequest memory)
    {
        return _removeVoteRequests[user][collection];
    }

    function getUserFreeVotes(address user) external view returns (uint256) {
        return _freeVotes[user];
    }

    function getUserCollectionVotes(address user, address collection)
        external
        view
        returns (uint256)
    {
        return _votes[user][collection];
    }

    function getCollateralizationBoost(address user, address collection)
        external
        view
        override
        returns (uint256)
    {
        uint256 boost;

        uint256 userCollectionActiveLoansCount = ILoanCenter(
            _addressProvider.getLoanCenter()
        ).getUserCollectionActiveLoansCount(user, collection);

        uint256 collectionFloorPrice = INFTOracle(
            _addressProvider.getNFTOracle()
        ).getCollectionFloorPrice(collection);

        uint256 nativeTokenPrice = ITokenOracle(
            _addressProvider.getTokenOracle()
        ).getTokenPrice(_nativeToken);

        uint256 votesValue = _collectionVotes[collection] * nativeTokenPrice;

        uint256 activeLoansAssetValue = userCollectionActiveLoansCount *
            collectionFloorPrice;

        if (activeLoansAssetValue != 0) {
            boost =
                (PercentageMath.PERCENTAGE_FACTOR * votesValue) /
                (activeLoansAssetValue * boostMultiplier);
        } else {
            boost = 0;
        }

        return boost;
    }

    function getLockedBalance() external view override returns (uint256) {
        return _getLockedBalance();
    }

    function _getLockedBalance() internal view returns (uint256) {
        return IERC20Upgradeable(_nativeToken).balanceOf(address(this));
    }

    function getMaximumWithdrawalAmount(address user)
        external
        view
        returns (uint256)
    {
        uint256 veTokenFreeAmount = _freeVotes[user];
        uint256 maximumAmount;

        if (veTokenFreeAmount == 0) {
            maximumAmount = 0;
        } else {
            maximumAmount =
                (veTokenFreeAmount * _getLockedBalance()) /
                totalSupply();
        }

        return maximumAmount;
    }

    // Override transfer functions so the token is not transferable
    function transfer(address, uint256) public pure override returns (bool) {
        revert("Transfer disabled");
    }

    function transferFrom(
        address,
        address,
        uint256
    ) public pure override returns (bool) {
        revert("Transfer disabled");
    }
}
