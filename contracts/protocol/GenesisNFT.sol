// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.8.19;

import {IAddressesProvider} from "../interfaces/IAddressesProvider.sol";
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
import {ERC721Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC721/ERC721Upgradeable.sol";
import {IERC165Upgradeable} from "@openzeppelin/contracts-upgradeable/utils/introspection/IERC165Upgradeable.sol";
import {CountersUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/CountersUpgradeable.sol";
import {ERC721EnumerableUpgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC721/extensions/ERC721EnumerableUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {ContextUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ContextUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import {IVault} from "@balancer-labs/v2-interfaces/contracts/vault/IVault.sol";
import {WeightedPoolUserData} from "@balancer-labs/v2-interfaces/contracts/pool-weighted/WeightedPoolUserData.sol";
import {IBalancerQueries} from "@balancer-labs/v2-interfaces/contracts/standalone-utils/IBalancerQueries.sol";
// solhint-disable-next-line no-global-import
import "../libraries/balancer/ERC20Helpers.sol"; // Custom (pragma ^0.8.0) ERC20 helpers for Balancer tokens

/// @title GenesisNFT
/// @notice This contract manages the creation and minting of Genesis NFTs
contract GenesisNFT is
    ContextUpgradeable,
    ERC165Upgradeable,
    ERC721EnumerableUpgradeable,
    OwnableUpgradeable,
    IGenesisNFT,
    ReentrancyGuardUpgradeable
{
    uint256 private constant LP_LE_AMOUNT = 8000e18; // 8000 LE
    uint256 private constant LP_ETH_AMOUNT = 20e16; // 0.2 ETH

    using CountersUpgradeable for CountersUpgradeable.Counter;
    using SafeERC20Upgradeable for IERC20Upgradeable;

    IAddressesProvider private _addressProvider;
    uint256 private _cap;
    uint256 private _price;
    uint256 private _maxLocktime;
    uint256 private _minLocktime;
    uint256 private _nativeTokenFactor;
    DataTypes.BalancerDetails private _balancerDetails;
    address private _balancerPoolId;
    address payable private _devAddress;
    uint256 private _maxLTVBoost;
    CountersUpgradeable.Counter private _tokenIdCounter;
    // Mapping from owner to create loan operator approvals
    mapping(address => mapping(address => bool)) private _loanOperatorApprovals;

    // NFT token id to bool that's true if NFT is being used to increase a loan's max LTV
    mapping(uint256 => bool) private _locked;

    // NFT token id to information about its mint
    mapping(uint256 => DataTypes.MintDetails) private _mintDetails;

    modifier onlyMarket() {
        _requireOnlyMarket();
        _;
    }

    modifier tokenExists(uint256 tokenId) {
        _requireTokenExists(tokenId);
        _;
    }

    modifier validPool() {
        _requireValidPool();
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
    /// @param maxLTVBoost max LTV boost factor
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
        uint256 maxLTVBoost,
        uint256 nativeTokenFactor,
        uint256 maxLocktime,
        uint256 minLocktime,
        address payable devAddress
    ) external initializer {
        require(price >= LP_ETH_AMOUNT, "G:I:PRICE_TOO_LOW");
        __ERC721_init(name, symbol);
        __ERC721Enumerable_init();
        __ERC165_init();
        __Ownable_init();
        __ReentrancyGuard_init();
        __Context_init();
        _addressProvider = addressProvider;
        _cap = cap;
        _price = price;
        _maxLTVBoost = maxLTVBoost;
        _nativeTokenFactor = nativeTokenFactor;
        _maxLocktime = maxLocktime;
        _minLocktime = minLocktime;
        _devAddress = devAddress;

        // Start from token_id 1 in order to reserve '0' for the null token
        _tokenIdCounter.increment();
    }

    /// @notice Sets an approved address as a loan operator for the caller
    /// @dev This approval allows for the use of the genesis NFT by the loan operator in a loan
    /// @param operator Address to set approval for
    /// @param approved True if the operator is approved, false to revoke approval
    function setLoanOperatorApproval(address operator, bool approved) external {
        _loanOperatorApprovals[_msgSender()][operator] = approved;
    }

    /// @notice Checks if an address is approved as a loan operator for an owner
    /// @param owner Address of the owner
    /// @param operator Address of the operator
    /// @return True if the operator is approved, false otherwise
    function isLoanOperatorApproved(
        address owner,
        address operator
    ) external view returns (bool) {
        return _loanOperatorApprovals[owner][operator];
    }

    /// @notice Returns the URI for a given token ID
    /// @param tokenId ID of the token
    /// @return The token's URI
    function tokenURI(
        uint256 tokenId
    )
        public
        view
        override(ERC721Upgradeable)
        tokenExists(tokenId)
        returns (string memory)
    {
        require(_exists(tokenId), "G:TU:INVALID_TOKEN_ID");
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
                            Base64.encode(svg(tokenId)),
                            '",',
                            '"attributes": [',
                            string(
                                abi.encodePacked(
                                    '{ "trait_type": "locked", "value": "',
                                    _locked[tokenId] ? "true" : "false",
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

    function svg(
        uint256 tokenId
    ) public view tokenExists(tokenId) returns (bytes memory _svg) {
        require(_exists(tokenId), "G:S:INVALID_TOKEN_ID");
        {
            _svg = abi.encodePacked(
                '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 400 400" style="width:100%;background:#f8f1f1;fill:#000;font-family:monospace">',
                "<defs>",
                '<filter id="a">',
                '<feGaussianBlur in="SourceGraphic" stdDeviation="2" result="blur"/>',
                "<feMerge>",
                '<feMergeNode in="blur"/>',
                '<feMergeNode in="SourceGraphic"/>',
                "</feMerge>",
                "</filter>",
                "</defs>",
                '<text x="50%" y="30%" text-anchor="middle" font-size="18" letter-spacing="2">',
                '<tspan dy="0">leNFT</tspan>',
                '<animate attributeName="textLength" from="0" to="40%" dur="1.8s" fill="freeze"/>',
                '<animate attributeName="lengthAdjust" to="spacing" dur="1.4s" fill="freeze"/>',
                "</text>"
            );
        }

        {
            _svg = abi.encodePacked(
                _svg,
                '<circle cx="50%" cy="60%" r="50" fill="none" stroke="#000" stroke-width="2" filter="url(#a)"/>',
                '<text x="50%" text-anchor="middle" font-size="28">',
                '<tspan dy="180">',
                Strings.toString(tokenId),
                "</tspan>",
                '<animate attributeName="y" values="-100;70;65;70" keyTimes="0;0.8;0.9;1" dur="1s" fill="freeze"/>',
                "</text>",
                '<text font-size="12" letter-spacing="4" rotate="180 180 180 180 180 180 180">',
                '<textPath href="#b" startOffset="0%">',
                "SISENEG",
                '<animate attributeName="startOffset" from="100%" to="0%" dur="15s" repeatCount="indefinite"/>',
                "</textPath>",
                "</text>"
            );
        }

        {
            _svg = abi.encodePacked(
                _svg,
                "<defs>",
                '<path id="b" d="M140 240a60 60 0 1 0 120 0 60 60 0 1 0-120 0"/>',
                "</defs>",
                "</svg>"
            );
        }
    }

    /// @notice Returns the maximum number of tokens that can be minted
    /// @return The maximum number of tokens
    function getCap() public view returns (uint256) {
        return _cap;
    }

    /// @notice Returns the max LTV boost factor
    /// @return The max LTV boost factor
    function getMaxLTVBoost() external view override returns (uint256) {
        return _maxLTVBoost;
    }

    /// @notice Sets the Max LTV boost factor
    /// @param newMaxLTVBoost The new Max LTV boost factor
    function setMaxLTVBoost(uint256 newMaxLTVBoost) external onlyOwner {
        _maxLTVBoost = newMaxLTVBoost;
    }

    /// @notice Returns the active state of the specified Genesis NFT
    /// @param tokenId ID of the token
    /// @return The active state
    function getLockedState(
        uint256 tokenId
    ) external view override tokenExists(tokenId) returns (bool) {
        return _locked[tokenId];
    }

    /// @notice Sets the active state of the specified Genesis NFT
    /// @param tokenId ID of the token
    /// @param newState The new active state
    function setLockedState(
        uint256 tokenId,
        bool newState
    ) external override tokenExists(tokenId) onlyMarket {
        _locked[tokenId] = newState;
    }

    /// @notice Calculates the native token reward for a given amount and lock time
    /// @param amount Amount of tokens to be minted
    /// @param locktime Lock time for lock in seconds
    /// @return The native token reward
    function getCurrentLEReward(
        uint256 amount,
        uint256 locktime
    ) public view returns (uint256) {
        require(_tokenIdCounter.current() <= _cap, "G:GNTR:MINT_OVER");
        require(locktime >= _minLocktime, "G:GNTR:LOCKTIME_TOO_LOW");
        require(locktime <= _maxLocktime, "G:GNTR:LOCKTIME_TOO_HIGH");

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
    /// @param locktime The time for which the tokens yielded by the genesis NFT are locked for
    /// @param amount The amount of tokens to mint
    function mint(
        uint256 locktime,
        uint256 amount
    ) external payable nonReentrant validPool {
        // Make sure amount is bigger than 0
        require(amount > 0, "G:M:AMOUNT_0");
        // Make sure locktimes are within limits
        require(locktime >= _minLocktime, "G:M:LOCKTIME_TOO_LOW");
        require(locktime <= _maxLocktime, "G:M:LOCKTIME_TOO_HIGH");

        // Make sure there are enough tokens to mint
        require(
            _tokenIdCounter.current() + amount <= getCap(),
            "G:M:CAP_EXCEEDED"
        );

        // Get the native token address to save on gas
        address nativeToken = _addressProvider.getNativeToken();

        // Make sure the user sent enough ETH
        require(msg.value == _price * amount, "G:M:INSUFFICIENT_ETH");

        // Get the amount of ETH to deposit to the pool
        uint256 ethAmount = LP_ETH_AMOUNT * amount;
        uint256 leAmount = LP_LE_AMOUNT * amount;

        // Mint LE tokens
        uint256 totalRewards = getCurrentLEReward(amount, locktime);
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
        (bool sent, ) = _devAddress.call{value: _price * amount - ethAmount}(
            ""
        );
        require(sent, "G:M:ETH_TRANSFER_FAIL");

        for (uint256 i = 0; i < amount; i++) {
            // Mint genesis NFT
            _safeMint(_msgSender(), _tokenIdCounter.current());

            // Add mint details
            _mintDetails[_tokenIdCounter.current()] = DataTypes.MintDetails(
                block.timestamp,
                locktime,
                lpAmount / amount
            );

            emit Mint(_msgSender(), _tokenIdCounter.current());

            //Increase supply
            _tokenIdCounter.increment();
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
    function getUnlockTimestamp(
        uint256 tokenId
    ) public view tokenExists(tokenId) returns (uint256) {
        return _mintDetails[tokenId].timestamp + _mintDetails[tokenId].locktime;
    }

    /// @notice Burn Genesis NFTs and unlock LP tokens and LE tokens
    /// @param tokenIds The IDs of the Genesis NFTs to burn
    function burn(uint256[] calldata tokenIds) external validPool nonReentrant {
        // Make sure we are burning at least one token
        require(tokenIds.length > 0, "G:B:0_TOKENS");
        uint256 lpAmountSum;
        for (uint256 i = 0; i < tokenIds.length; i++) {
            //Require the caller owns the token
            require(_msgSender() == ownerOf(tokenIds[i]), "G:B:NOT_OWNER");
            // Token can only be burned after locktime is over
            require(
                block.timestamp >= getUnlockTimestamp(tokenIds[i]),
                "G:B:NOT_UNLOCKED"
            );

            // Add the LP amount to the sum
            lpAmountSum += _mintDetails[tokenIds[i]].lpAmount;

            // Burn genesis NFT
            _burn(tokenIds[i]);
            emit Burn(tokenIds[i]);
        }
        // Get the native token address to save on gas
        address nativeTokenAddress = _addressProvider.getNativeToken();

        // Withdraw LP tokens from the pool
        (IERC20[] memory tokens, , ) = IVault(_balancerDetails.vault)
            .getPoolTokens(_balancerDetails.poolId);

        uint256 oldLEBalance = IERC20Upgradeable(nativeTokenAddress).balanceOf(
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
                    _findTokenIndex(tokens, IERC20(nativeTokenAddress))
                ),
                toInternalBalance: false
            })
        );

        uint256 withdrawAmount = IERC20Upgradeable(nativeTokenAddress)
            .balanceOf(address(this)) - oldLEBalance;
        uint256 burnTokens = LP_LE_AMOUNT * tokenIds.length;
        if (withdrawAmount > burnTokens) {
            // Send the rest of the LE tokens to the owner of the Genesis NFT
            IERC20Upgradeable(nativeTokenAddress).transfer(
                _msgSender(),
                withdrawAmount - burnTokens
            );
        } else {
            burnTokens = withdrawAmount;
        }
        if (burnTokens > 0) {
            INativeToken(nativeTokenAddress).burnGenesisTokens(burnTokens);
        }
    }

    /// @notice Get the current value of the LP tokens locked in the contract
    /// @param tokenIds The tokens ids of the genesis NFTs associated with the LP tokens
    /// @return The value of the LP tokens in wei
    function getLPValueInLE(
        uint256[] calldata tokenIds
    ) external validPool returns (uint256) {
        uint256 lpAmountSum;
        IVault vault = IVault(_balancerDetails.vault);
        for (uint256 i = 0; i < tokenIds.length; i++) {
            // Make sure the token exists
            require(_exists(tokenIds[i]), "G:GLPVLE:NOT_FOUND");
            // Add the LP amount to the sum
            lpAmountSum += _mintDetails[tokenIds[i]].lpAmount;
        }

        (IERC20[] memory tokens, , ) = vault.getPoolTokens(
            _balancerDetails.poolId
        );
        uint256[] memory minAmountsOut = new uint256[](2);
        uint256 leIndex = _findTokenIndex(
            tokens,
            IERC20(_addressProvider.getNativeToken())
        );
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
    ) internal override(ERC721EnumerableUpgradeable) {
        require(_locked[tokenId] == false, "G:BTT:TOKEN_LOCKED");
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
            ERC721EnumerableUpgradeable,
            ERC165Upgradeable,
            IERC165Upgradeable
        )
        returns (bool)
    {
        return
            ERC721EnumerableUpgradeable.supportsInterface(interfaceId) ||
            ERC165Upgradeable.supportsInterface(interfaceId);
    }

    function _requireOnlyMarket() internal view {
        require(
            _msgSender() == _addressProvider.getLendingMarket(),
            "G:NOT_MARKET"
        );
    }

    function _requireTokenExists(uint256 tokenId) internal view {
        require(_exists(tokenId), "G:TOKEN_NOT_FOUND");
    }

    function _requireValidPool() internal view {
        require(_balancerDetails.pool != address(0), "G:M:BALANCER_NOT_SET");
        (IERC20[] memory tokens, , ) = IVault(_balancerDetails.vault)
            .getPoolTokens(_balancerDetails.poolId);
        // Make sure there are only two assets in the pool
        require(tokens.length == 2, "G:M:INVALID_POOL_LENGTH");
        // Make sure those two assets are the native token and WETH
        for (uint i = 0; i < tokens.length; i++) {
            require(
                tokens[i] == IERC20(_addressProvider.getNativeToken()) ||
                    tokens[i] == IERC20(_addressProvider.getWETH()),
                "G:B:INVALID_POOL_TOKENS"
            );
        }
    }

    // Function to receive Ether
    receive() external payable {
        revert("G:RECEIVE_NOT_ALLOWED");
    }
}
