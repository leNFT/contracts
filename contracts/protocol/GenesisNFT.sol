// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.8.19;

import {IAddressesProvider} from "../interfaces/IAddressesProvider.sol";
import {ILendingMarket} from "../interfaces/ILendingMarket.sol";
import {IWETH} from "../interfaces/IWETH.sol";
import {Base64} from "@openzeppelin/contracts/utils/Base64.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {IGenesisNFT} from "../interfaces/IGenesisNFT.sol";
import {INativeToken} from "../interfaces/INativeToken.sol";
import {IVotingEscrow} from "../interfaces/IVotingEscrow.sol";
import {DataTypes} from "../libraries/types/DataTypes.sol";
import {SafeERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import {IERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import {ERC165Upgradeable} from "@openzeppelin/contracts-upgradeable/utils/introspection/ERC165Upgradeable.sol";
import {IERC165Upgradeable} from "@openzeppelin/contracts-upgradeable/utils/introspection/IERC165Upgradeable.sol";
import {ERC721Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC721/ERC721Upgradeable.sol";
import {CountersUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/CountersUpgradeable.sol";
import {ERC721EnumerableUpgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC721/extensions/ERC721EnumerableUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {ContextUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ContextUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import {IVault} from "@balancer-labs/v2-interfaces/contracts/vault/IVault.sol";
import {WeightedPoolUserData} from "@balancer-labs/v2-interfaces/contracts/pool-weighted/WeightedPoolUserData.sol";
import {IBalancerQueries} from "@balancer-labs/v2-interfaces/contracts/standalone-utils/IBalancerQueries.sol";
import "@balancer-labs/v2-solidity-utils/contracts/helpers/ERC20Helpers.sol";
import "hardhat/console.sol";

/// @title GenesisNFT
/// @notice This contract manages the creation and minting of Genesis NFTs
contract GenesisNFT is
    Initializable,
    ContextUpgradeable,
    ERC165Upgradeable,
    ERC721Upgradeable,
    ERC721EnumerableUpgradeable,
    OwnableUpgradeable,
    IGenesisNFT,
    ReentrancyGuardUpgradeable
{
    uint256 constant LP_LE_AMOUNT = 1000e18; // 1000 LE
    uint256 constant LP_ETH_AMOUNT = 20e16; // 0.2 ETH

    using CountersUpgradeable for CountersUpgradeable.Counter;
    using SafeERC20Upgradeable for IERC20Upgradeable;

    IAddressesProvider private _addressProvider;
    uint256 _cap;
    uint256 _price;
    uint256 _maxLocktime;
    uint256 _minLocktime;
    uint256 _nativeTokenFactor;
    DataTypes.BalancerDetails _balancerDetails;
    address _balancerPoolId;
    address payable _devAddress;
    uint256 _ltvBoost;
    CountersUpgradeable.Counter private _tokenIdCounter;

    // NFT token id to bool that's true if NFT is being used to charge a loan
    mapping(uint256 => bool) private _active;

    // NFT token id to information about its mint
    mapping(uint256 => DataTypes.MintDetails) private _mintDetails;

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

    /// @notice Initializes the contract with the specified parameters
    /// @param addressProvider Address provider contract
    /// @param name Name of the NFT
    /// @param symbol Symbol of the NFT
    /// @param cap Maximum number of tokens that can be minted
    /// @param price Price of each NFT in wei
    /// @param ltvBoost LTV boost factor
    /// @param nativeTokenFactor Factor for calculating native token reward
    /// @param maxLocktime Maximum lock time for staking in seconds
    /// @param minLocktime Minimum lock time for staking in seconds
    /// @param devAddress Address of the developer
    function initialize(
        IAddressesProvider addressProvider,
        string calldata name,
        string calldata symbol,
        uint256 cap,
        uint256 price,
        uint256 ltvBoost,
        uint256 nativeTokenFactor,
        uint256 maxLocktime,
        uint256 minLocktime,
        address payable devAddress
    ) external initializer {
        require(
            price >= LP_ETH_AMOUNT,
            "Price must be greater or equal to LP ETH AMOUNT"
        );
        __ERC721_init(name, symbol);
        __ERC721Enumerable_init();
        __Ownable_init();
        _addressProvider = addressProvider;
        _cap = cap;
        _price = price;
        _ltvBoost = ltvBoost;
        _nativeTokenFactor = nativeTokenFactor;
        _maxLocktime = maxLocktime;
        _minLocktime = minLocktime;
        _devAddress = devAddress;

        // Start from token_id 1 in order to reserve '0' for the null token
        _tokenIdCounter.increment();
    }

    /// @notice Returns the URI for a given token ID
    /// @param tokenId ID of the token
    /// @return The URI
    function tokenURI(
        uint256 tokenId
    ) public view override(ERC721Upgradeable) returns (string memory) {
        return
            string(
                abi.encodePacked(
                    "data:application/json;base64,",
                    Base64.encode(
                        abi.encodePacked(
                            "{",
                            '"name": "Genesis NFT #',
                            Strings.toString(tokenId),
                            '",',
                            '"description": "leNFT Genesis Collection NFT.",',
                            '"image": ',
                            '"data:image/svg+xml;base64,',
                            Base64.encode(
                                abi.encodePacked(
                                    '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 400 400" style="width:100%;background:#f8f1f1;fill:black;font-family:monospace">',
                                    '<text x="50%" y="30%" text-anchor="middle" font-size="18">',
                                    "leNFT Genesis",
                                    "</text>",
                                    '<text x="50%" y="50%" text-anchor="middle" font-size="28">',
                                    "#",
                                    Strings.toString(tokenId),
                                    "</text>",
                                    "</svg>"
                                )
                            ),
                            '",',
                            '"attributes": [',
                            string(
                                abi.encodePacked(
                                    '{ "trait_type": "locked", "value": "',
                                    _active[tokenId] ? "yes" : "no",
                                    '" },',
                                    '{ "trait_type": "unlock_timestamp", "value": "',
                                    Strings.toString(
                                        getUnlockTimestamp(tokenId)
                                    ),
                                    '" },',
                                    '{ "trait_type": "lp_amount", "value": "',
                                    Strings.toString(
                                        _mintDetails[tokenId].lpAmount
                                    ),
                                    '" }'
                                )
                            ),
                            "]",
                            "}"
                        )
                    )
                )
            );
    }

    /// @notice Returns the maximum number of tokens that can be minted
    /// @return The maximum number of tokens
    function getCap() public view returns (uint256) {
        return _cap;
    }

    /// @notice Returns the LTV boost factor
    /// @return The LTV boost factor
    function getLTVBoost() external view override returns (uint256) {
        return _ltvBoost;
    }

    /// @notice Sets the LTV boost factor
    /// @param newLTVBoost The new LTV boost factor
    function setLTVBoost(uint256 newLTVBoost) external onlyOwner {
        _ltvBoost = newLTVBoost;
    }

    /// @notice Returns the active state of the specified Genesis NFT
    /// @param tokenId ID of the token
    /// @return The active state
    function getActiveState(
        uint256 tokenId
    ) external view override returns (bool) {
        return _active[tokenId];
    }

    /// @notice Sets the active state of the specified Genesis NFT
    /// @param tokenId ID of the token
    /// @param newState The new active state
    function setActiveState(
        uint256 tokenId,
        bool newState
    ) external override onlyMarket {
        _active[tokenId] = newState;
    }

    /// @notice Calculates the native token reward for a given amount and lock time
    /// @param amount Amount of tokens to be minted
    /// @param locktime Lock time for lock in seconds
    /// @return The native token reward
    function getNativeTokenReward(
        uint256 amount,
        uint256 locktime
    ) public view returns (uint256) {
        require(locktime >= _minLocktime, "Locktime is lower than threshold");
        require(locktime <= _maxLocktime, "Locktime is higher than limit");

        if (_tokenIdCounter.current() > _cap) {
            return 0;
        }

        return
            ((amount * locktime * (_cap - (_tokenIdCounter.current() / 2))) /
                _nativeTokenFactor) * 1e18;
    }

    /// @notice Sets the details of the balancer subsidized trading pool
    /// @param balancerDetails Addresses of the balancer contracts
    function setBalancerDetails(
        DataTypes.BalancerDetails calldata balancerDetails
    ) external onlyOwner {
        _balancerDetails = balancerDetails;
    }

    /// @notice Returns the number of tokens that have been minted
    /// @return The number of tokens
    function mintCount() external view returns (uint256) {
        return _tokenIdCounter.current() - 1;
    }

    /// @notice Mint new Genesis NFTs with locked LE tokens and LP tokens
    /// @param locktime The locktime for the minted tokens
    /// @param amount The amount of tokens to mint
    function mint(
        uint256 locktime,
        uint256 amount
    ) external payable nonReentrant {
        // Make sure locktimes are within limits
        require(locktime >= _minLocktime, "Locktime is lower than threshold");
        require(locktime <= _maxLocktime, "Locktime is higher than limit");

        // Make sure the genesis incentived pool is set
        require(
            _balancerDetails.poolId != bytes32(0) &&
                _balancerDetails.pool != address(0),
            "Balancer Details not set."
        );

        // Make sure there are enough tokens to mint
        require(
            _tokenIdCounter.current() + amount <= getCap(),
            "Maximum cap exceeded"
        );

        // Get the native token address to save on gas
        address nativeToken = _addressProvider.getNativeToken();

        // Make sure the user sent enough ETH
        uint256 buyPrice = _price * amount;
        require(msg.value == buyPrice, "Tx value is not equal to price");

        // Get the amount of ETH to deposit to the pool
        uint256 ethAmount = LP_ETH_AMOUNT * amount;
        uint256 leAmount = LP_LE_AMOUNT * amount;

        // Mint LE tokens
        uint256 totalRewards = getNativeTokenReward(amount, locktime);
        INativeToken(nativeToken).mintGenesisTokens(leAmount + totalRewards);

        // Mint WETH tokens
        IWETH(_addressProvider.getWETH()).deposit{value: ethAmount}();

        // Approve the vault to spend LE & WETH tokens
        IERC20Upgradeable(nativeToken).approve(
            _balancerDetails.vault,
            leAmount
        );
        IERC20Upgradeable(_addressProvider.getWETH()).approve(
            _balancerDetails.vault,
            ethAmount
        );

        // Deposit tokens to the pool and get the LP amount
        uint256 oldLPBalance = IERC20Upgradeable(_balancerDetails.pool)
            .balanceOf(address(this));

        (IERC20[] memory tokens, , ) = IVault(_balancerDetails.vault)
            .getPoolTokens(_balancerDetails.poolId);

        uint256[] memory maxAmountsIn = new uint256[](2);
        uint256[] memory amountsToEncode = new uint256[](2);

        amountsToEncode[
            _findTokenIndex(tokens, IERC20(nativeToken))
        ] = leAmount;
        amountsToEncode[
            _findTokenIndex(tokens, IERC20(_addressProvider.getWETH()))
        ] = ethAmount;
        maxAmountsIn[0] = type(uint256).max;
        maxAmountsIn[1] = type(uint256).max;
        bytes memory userData;

        if (IERC20Upgradeable(_balancerDetails.pool).totalSupply() == 0) {
            userData = abi.encode(
                WeightedPoolUserData.JoinKind.INIT,
                amountsToEncode
            );
        } else {
            userData = abi.encode(
                WeightedPoolUserData.JoinKind.EXACT_TOKENS_IN_FOR_BPT_OUT,
                amountsToEncode,
                "0"
            );
        }

        // Call the Vault to join the pool
        IVault(_balancerDetails.vault).joinPool(
            _balancerDetails.poolId,
            address(this),
            address(this),
            IVault.JoinPoolRequest({
                assets: _asIAsset(tokens),
                maxAmountsIn: maxAmountsIn,
                userData: userData,
                fromInternalBalance: false
            })
        );

        uint256 lpAmount = IERC20Upgradeable(_balancerDetails.pool).balanceOf(
            address(this)
        ) - oldLPBalance;

        // Approve the voting escrow to spend LE tokens so they can be locked
        IERC20Upgradeable(nativeToken).approve(
            _addressProvider.getVotingEscrow(),
            totalRewards
        );

        IVotingEscrow(_addressProvider.getVotingEscrow()).createLock(
            _msgSender(),
            totalRewards,
            block.timestamp + locktime
        );

        // Send the rest of the ETH to the dev address
        (bool sent, ) = _devAddress.call{value: buyPrice - ethAmount}("");
        require(sent, "Failed to send Ether to dev fund");

        uint256 tokenId;
        for (uint256 i = 0; i < amount; i++) {
            tokenId = _tokenIdCounter.current();

            // Mint genesis NFT
            _safeMint(_msgSender(), tokenId);

            // Add mint details
            _mintDetails[tokenId] = DataTypes.MintDetails(
                block.timestamp,
                locktime,
                lpAmount / amount
            );

            //Increase supply
            _tokenIdCounter.increment();

            emit Mint(_msgSender(), tokenId);
        }
    }

    /// @notice Get the current price for minting Genesis NFTs
    /// @return The current price in wei
    function getPrice() external view returns (uint256) {
        return _price;
    }

    /// @notice Get the unlock timestamp for a specific Genesis NFT
    /// @param tokenId The ID of the Genesis NFT to check
    /// @return The unlock timestamp for the specified token
    function getUnlockTimestamp(uint256 tokenId) public view returns (uint256) {
        return _mintDetails[tokenId].timestamp + _mintDetails[tokenId].locktime;
    }

    /// @notice Burn Genesis NFTs and unlock LP tokens and LE tokens
    /// @param tokenIds The IDs of the Genesis NFTs to burn
    function burn(uint256[] calldata tokenIds) external nonReentrant {
        uint256 lpAmountSum = 0;
        for (uint256 i = 0; i < tokenIds.length; i++) {
            //Require the caller owns the token
            require(
                _msgSender() == ERC721Upgradeable.ownerOf(tokenIds[i]),
                "Must own token"
            );
            // Token can only be burned after locktime is over
            require(
                block.timestamp >= getUnlockTimestamp(tokenIds[i]),
                "Token is still locked"
            );

            // Add the LP amount to the sum
            lpAmountSum += _mintDetails[tokenIds[i]].lpAmount;

            // Burn genesis NFT
            _burn(tokenIds[i]);
            emit Burn(tokenIds[i]);
        }
        // Get the native token address to save on gas
        address nativeToken = _addressProvider.getNativeToken();

        // Withdraw LP tokens from the pool
        (IERC20[] memory tokens, , ) = IVault(_balancerDetails.vault)
            .getPoolTokens(_balancerDetails.poolId);
        uint256 oldLEBalance = IERC20Upgradeable(nativeToken).balanceOf(
            address(this)
        );

        uint256[] memory minAmountsOut = new uint256[](2);
        // Call the Vault to exit the pool
        IVault(_balancerDetails.vault).exitPool(
            _balancerDetails.poolId,
            address(this),
            payable(this),
            IVault.ExitPoolRequest({
                assets: _asIAsset(tokens),
                minAmountsOut: minAmountsOut,
                userData: abi.encode(
                    WeightedPoolUserData
                        .ExitKind
                        .EXACT_BPT_IN_FOR_ONE_TOKEN_OUT,
                    lpAmountSum,
                    _findTokenIndex(tokens, IERC20(nativeToken))
                ),
                toInternalBalance: false
            })
        );

        uint256 withdrawAmount = IERC20Upgradeable(nativeToken).balanceOf(
            address(this)
        ) - oldLEBalance;
        uint256 burnTokens = LP_LE_AMOUNT * tokenIds.length;
        if (withdrawAmount > burnTokens) {
            // Send the rest of the LE tokens to the owner of the Genesis NFT
            IERC20Upgradeable(nativeToken).transfer(
                _msgSender(),
                withdrawAmount - burnTokens
            );
        } else {
            burnTokens = withdrawAmount;
        }
        INativeToken(nativeToken).burnGenesisTokens(burnTokens);
    }

    /// @notice Get the current value of the LP tokens locked in the contract
    /// @param tokenIds The tokens ids of the genesis NFTs associated with the LP tokens
    /// @return The value of the LP tokens in wei
    function getLPValueInLE(
        uint256[] calldata tokenIds
    ) external returns (uint256) {
        uint256 lpAmountSum = 0;
        IVault vault = IVault(_balancerDetails.vault);
        for (uint256 i = 0; i < tokenIds.length; i++) {
            // Add the LP amount to the sum
            lpAmountSum += _mintDetails[tokenIds[i]].lpAmount;
        }

        (IERC20[] memory tokens, , ) = vault.getPoolTokens(
            _balancerDetails.poolId
        );
        uint256 leIndex = _findTokenIndex(
            tokens,
            IERC20(_addressProvider.getNativeToken())
        );
        uint256[] memory minAmountsOut = new uint256[](2);

        // Calculate the value of the LP tokens in LE tokens
        (, uint256[] memory amountsOut) = IBalancerQueries(
            _balancerDetails.queries
        ).queryExit(
                _balancerDetails.poolId,
                address(this),
                address(this),
                IVault.ExitPoolRequest({
                    assets: _asIAsset(tokens),
                    minAmountsOut: minAmountsOut,
                    userData: abi.encode(
                        WeightedPoolUserData
                            .ExitKind
                            .EXACT_BPT_IN_FOR_ONE_TOKEN_OUT,
                        lpAmountSum,
                        leIndex
                    ),
                    toInternalBalance: false
                })
            );

        uint256 burnTokens = LP_LE_AMOUNT * tokenIds.length;
        if (amountsOut[leIndex] > burnTokens) {
            return amountsOut[leIndex] - burnTokens;
        }

        return 0;
    }

    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 tokenId,
        uint256 batchSize
    ) internal override(ERC721Upgradeable, ERC721EnumerableUpgradeable) {
        require(
            _active[tokenId] == false,
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
            ERC165Upgradeable,
            ERC721EnumerableUpgradeable,
            ERC721Upgradeable,
            IERC165Upgradeable
        )
        returns (bool)
    {
        return
            ERC721EnumerableUpgradeable.supportsInterface(interfaceId) ||
            ERC165Upgradeable.supportsInterface(interfaceId);
    }

    // Function to receive Ether
    receive() external payable {}
}
