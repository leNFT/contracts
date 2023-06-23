// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.8.19;

import {ITradingPool} from "../../interfaces/ITradingPool.sol";
import {IAddressProvider} from "../../interfaces/IAddressProvider.sol";
import {IPricingCurve} from "../../interfaces/IPricingCurve.sol";
import {IFeeDistributor} from "../../interfaces/IFeeDistributor.sol";
import {ITradingPoolFactory} from "../../interfaces/ITradingPoolFactory.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {ERC721Enumerable} from "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import {ERC721Holder} from "@openzeppelin/contracts/token/ERC721/utils/ERC721Holder.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC165} from "@openzeppelin/contracts/utils/introspection/ERC165.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {DataTypes} from "../../libraries/types/DataTypes.sol";
import {PercentageMath} from "../../libraries/utils/PercentageMath.sol";
import {ILiquidityPairMetadata} from "../../interfaces/ILiquidityPairMetadata.sol";
import {SafeCast} from "../../libraries/utils/SafeCast.sol";

/// @title Trading Pool Contract
/// @author leNFT
/// @notice A contract that enables the creation of liquidity pools and the trading of NFTs and ERC20 tokens.
/// @dev This contract manages liquidity pairs, each consisting of a set of NFTs and an ERC20 token, as well as the trading of these pairs.
contract TradingPool is
    ERC165,
    ERC721Enumerable,
    ERC721Holder,
    ITradingPool,
    Ownable,
    ReentrancyGuard
{
    uint public constant MAX_FEE = 8000; // 80%

    IAddressProvider private immutable _addressProvider;
    bool private _paused;
    address private immutable _token;
    address private immutable _nft;
    mapping(uint256 => DataTypes.LiquidityPair) private _liquidityPairs;
    mapping(uint256 => DataTypes.NftToLp) private _nftToLp;
    uint256 private _lpCount;

    using SafeERC20 for IERC20;

    modifier poolNotPaused() {
        _requirePoolNotPaused();
        _;
    }

    modifier lpExists(uint256 lpId) {
        _requireLpExists(lpId);
        _;
    }

    /// @notice Trading Pool constructor.
    /// @dev The constructor should only be called by the Trading Pool Factory contract.
    /// @param addressProvider The address provider contract.
    /// @param owner The owner of the Trading Pool contract.
    /// @param token The ERC20 token used in the trading pool.
    /// @param nft The address of the ERC721 contract.
    /// @param name The name of the ERC721 token.
    /// @param symbol The symbol of the ERC721 token.
    constructor(
        IAddressProvider addressProvider,
        address owner,
        address token,
        address nft,
        string memory name,
        string memory symbol
    ) ERC721(name, symbol) {
        require(
            msg.sender == addressProvider.getTradingPoolFactory(),
            "TP:C:MUST_BE_FACTORY"
        );
        _addressProvider = addressProvider;
        _token = token;
        _nft = nft;
        _transferOwnership(owner);
    }

    /// @notice Returns the token URI for a specific liquidity pair
    /// @param tokenId The ID of the liquidity pair.
    /// @return The token URI.
    function tokenURI(
        uint256 tokenId
    ) public view override lpExists(tokenId) returns (string memory) {
        return
            ILiquidityPairMetadata(_addressProvider.getLiquidityPairMetadata())
                .tokenURI(address(this), tokenId);
    }

    /// @notice Gets the address of the ERC721 traded in the pool.
    /// @return The address of the ERC721 token.
    function getNFT() external view override returns (address) {
        return _nft;
    }

    /// @notice Gets the address of the ERC20 token traded in the pool.
    /// @return The address of the ERC20 token.
    function getToken() external view override returns (address) {
        return _token;
    }

    /// @notice Gets the liquidity pair with the specified ID.
    /// @param lpId The ID of the liquidity pair.
    /// @return The liquidity pair.
    function getLP(
        uint256 lpId
    )
        external
        view
        override
        lpExists(lpId)
        returns (DataTypes.LiquidityPair memory)
    {
        return _liquidityPairs[lpId];
    }

    /// @notice Gets the number of liquidity pairs ever created in the trading pool.
    /// @return The number of liquidity pairs.
    function getLpCount() external view override returns (uint256) {
        return _lpCount;
    }

    /// @notice Gets the ID of the liquidity pair associated with the specified NFT.
    /// @param nftId The ID of the NFT.
    /// @return The ID of the liquidity pair.
    function nftToLp(uint256 nftId) external view override returns (uint256) {
        require(
            IERC721(_nft).ownerOf(nftId) == address(this),
            "TP:NTL:NOT_OWNED"
        );
        return _nftToLp[nftId].liquidityPair;
    }

    /// @notice Adds liquidity to the trading pool.
    /// @dev At least one of nftIds or tokenAmount must be greater than zero.
    /// @dev The caller must approve the Trading Pool contract to transfer the NFTs and ERC20 tokens.
    /// @param receiver The recipient of the liquidity pool tokens.
    /// @param nftIds The IDs of the NFTs being deposited.
    /// @param tokenAmount The amount of the ERC20 token being deposited.
    /// @param spotPrice The spot price of the liquidity pair being created.
    /// @param curve The pricing curve for the liquidity pair being created.
    /// @param delta The delta for the liquidity pair being created.
    /// @param fee The fee for the liquidity pair being created.
    function addLiquidity(
        address receiver,
        DataTypes.LPType lpType,
        uint256[] calldata nftIds,
        uint256 tokenAmount,
        uint256 spotPrice,
        address curve,
        uint256 delta,
        uint256 fee
    ) external override nonReentrant poolNotPaused {
        ITradingPoolFactory tradingPoolFactory = ITradingPoolFactory(
            _addressProvider.getTradingPoolFactory()
        );

        // Check if pool will exceed maximum permitted amount
        require(
            tokenAmount + IERC20(_token).balanceOf(address(this)) <
                tradingPoolFactory.getTVLSafeguard(),
            "TP:AL:SAFEGUARD_EXCEEDED"
        );

        // Different types of liquidity pairs have different requirements
        // Trade: Can contain NFTs and/or tokens
        // TradeUp: Can contain NFTs and/or tokens, delta must be > 0
        // TradeDown: Can contain NFTs and/or tokens, delta must be > 0
        // Buy: Can only contain tokens
        // Sell: Can only contain NFTs
        if (
            lpType == DataTypes.LPType.Trade ||
            lpType == DataTypes.LPType.TradeUp ||
            lpType == DataTypes.LPType.TradeDown
        ) {
            require(
                tokenAmount > 0 || nftIds.length > 0,
                "TP:AL:DEPOSIT_REQUIRED"
            );
        } else if (lpType == DataTypes.LPType.Buy) {
            require(tokenAmount > 0 && nftIds.length == 0, "TP:AL:TOKENS_ONLY");
        } else if (lpType == DataTypes.LPType.Sell) {
            require(nftIds.length > 0 && tokenAmount == 0, "TP:AL:NFTS_ONLY");
        }

        // Directional LPs must have a positive delta in order for the price to move or else
        // they degenerate into a Trade LPs with delta = 0
        if (
            lpType == DataTypes.LPType.TradeUp ||
            lpType == DataTypes.LPType.TradeDown
        ) {
            require(delta > 0, "TP:AL:DELTA_0");
        }

        if (lpType == DataTypes.LPType.Buy || lpType == DataTypes.LPType.Sell) {
            // Validate fee
            require(fee == 0, "TP:AL:INVALID_LIMIT_FEE");
        } else {
            // require that the fee is higher than 0 and less than the maximum fee
            require(fee > 0 && fee <= MAX_FEE, "TP:AL:INVALID_FEE");
        }

        // Require that the curve conforms to the curve interface
        require(tradingPoolFactory.isPriceCurve(curve), "TP:AL:INVALID_CURVE");

        // Validate LP params for chosen curve
        IPricingCurve(curve).validateLpParameters(spotPrice, delta, fee);

        // Add user nfts to the pool
        for (uint i = 0; i < nftIds.length; i++) {
            IERC721(_nft).safeTransferFrom(
                msg.sender,
                address(this),
                nftIds[i]
            );
            _nftToLp[nftIds[i]] = DataTypes.NftToLp({
                liquidityPair: SafeCast.toUint128(_lpCount),
                index: SafeCast.toUint128(i)
            });
        }

        // Send user token to the pool
        if (tokenAmount > 0) {
            IERC20(_token).safeTransferFrom(
                msg.sender,
                address(this),
                tokenAmount
            );
        }

        // Save the user deposit info
        _liquidityPairs[_lpCount] = DataTypes.LiquidityPair({
            lpType: lpType,
            nftIds: nftIds,
            tokenAmount: SafeCast.toUint128(tokenAmount),
            spotPrice: SafeCast.toUint128(spotPrice),
            curve: curve,
            delta: SafeCast.toUint128(delta),
            fee: SafeCast.toUint16(fee)
        });

        // Mint liquidity position NFT
        ERC721._safeMint(receiver, _lpCount);

        emit AddLiquidity(
            receiver,
            _lpCount,
            lpType,
            nftIds,
            tokenAmount,
            spotPrice,
            curve,
            delta,
            fee
        );

        _lpCount++;
    }

    /// @notice Removes liquidity pair, sending back deposited tokens and transferring the NFTs to the user
    /// @param lpId The ID of the LP token to remove
    function removeLiquidity(uint256 lpId) external override nonReentrant {
        _removeLiquidity(lpId);
    }

    /// @notice Removes liquidity pairs in batches by calling the removeLiquidity function for each LP token ID in the lpIds array
    /// @param lpIds The IDs of the LP tokens to remove liquidity from
    function removeLiquidityBatch(
        uint256[] calldata lpIds
    ) external override nonReentrant {
        for (uint i = 0; i < lpIds.length; i++) {
            _removeLiquidity(lpIds[i]);
        }
    }

    /// @notice Private function that removes a liquidity pair, sending back deposited tokens and transferring the NFTs to the user
    /// @param lpId The ID of the LP token to remove
    function _removeLiquidity(uint256 lpId) private {
        //Require the caller owns LP
        require(msg.sender == ERC721.ownerOf(lpId), "TP:RL:NOT_OWNER");

        // Send pool nfts to the user
        uint256 nftIdsLength = _liquidityPairs[lpId].nftIds.length;
        for (uint i = 0; i < nftIdsLength; i++) {
            IERC721(_nft).safeTransferFrom(
                address(this),
                msg.sender,
                _liquidityPairs[lpId].nftIds[i]
            );
            delete _nftToLp[_liquidityPairs[lpId].nftIds[i]];
        }

        // Send pool token back to user
        IERC20(_token).safeTransfer(
            msg.sender,
            _liquidityPairs[lpId].tokenAmount
        );

        // delete the user deposit info
        delete _liquidityPairs[lpId];

        // Burn liquidity position NFT
        ERC721._burn(lpId);

        emit RemoveLiquidity(msg.sender, lpId);
    }

    /// @notice Buys NFTs in exchange for pool tokens
    /// @param onBehalfOf The address to deposit the NFTs to
    /// @param nftIds The IDs of the NFTs to buy
    /// @param maximumPrice The maximum price the user is willing to pay for the NFTs
    /// @return finalPrice The final price paid for the NFTs
    function buy(
        address onBehalfOf,
        uint256[] calldata nftIds,
        uint256 maximumPrice
    )
        external
        override
        nonReentrant
        poolNotPaused
        returns (uint256 finalPrice)
    {
        require(nftIds.length > 0, "TP:B:NFTS_0");

        uint256 lpIndex;
        uint256 fee;
        uint256 totalProtocolFee;
        uint256 protocolFee;
        DataTypes.LiquidityPair memory lp;
        uint256 protocolFeePercentage = ITradingPoolFactory(
            _addressProvider.getTradingPoolFactory()
        ).getProtocolFeePercentage();
        for (uint i = 0; i < nftIds.length; i++) {
            // Check if the pool contract owns the NFT
            require(
                IERC721(_nft).ownerOf(nftIds[i]) == address(this),
                "TP:B:NOT_OWNER"
            );
            lpIndex = _nftToLp[nftIds[i]].liquidityPair;
            lp = _liquidityPairs[lpIndex];

            // Can't buy from buy LP
            require(lp.lpType != DataTypes.LPType.Buy, "TP:B:IS_BUY_LP");

            fee = PercentageMath.percentMul(lp.spotPrice, lp.fee);
            protocolFee = PercentageMath.percentMul(fee, protocolFeePercentage);

            // Remove nft from liquidity pair nft list
            _liquidityPairs[lpIndex].nftIds[_nftToLp[nftIds[i]].index] = lp
                .nftIds[lp.nftIds.length - 1];

            // Update NFT to lp tracker
            _nftToLp[lp.nftIds[lp.nftIds.length - 1]].index = _nftToLp[
                nftIds[i]
            ].index;
            delete _nftToLp[nftIds[i]];
            _liquidityPairs[lpIndex].nftIds.pop();

            _liquidityPairs[lpIndex].tokenAmount += SafeCast.toUint128(
                (lp.spotPrice + fee - protocolFee)
            );

            // Increase total price and fee sum
            finalPrice += (lp.spotPrice + fee);
            totalProtocolFee += protocolFee;

            // Update liquidity pair price
            if (lp.lpType != DataTypes.LPType.TradeDown) {
                _liquidityPairs[lpIndex].spotPrice = SafeCast.toUint128(
                    IPricingCurve(lp.curve).priceAfterBuy(
                        lp.spotPrice,
                        lp.delta,
                        lp.fee
                    )
                );
            }

            // Send NFT to user
            IERC721(_nft).safeTransferFrom(
                address(this),
                onBehalfOf,
                nftIds[i]
            );
        }

        require(finalPrice <= maximumPrice, "TP:B:MAX_PRICE_EXCEEDED");

        // Get tokens from user
        IERC20(_token).safeTransferFrom(msg.sender, address(this), finalPrice);

        // Send protocol fee to protocol fee distributor
        address feeDistributor = _addressProvider.getFeeDistributor();
        IERC20(_token).safeTransfer(feeDistributor, totalProtocolFee);
        IFeeDistributor(feeDistributor).checkpoint(_token);

        emit Buy(onBehalfOf, nftIds, finalPrice);
    }

    /// @notice Allows an address to sell one or more NFTs in exchange for a token amount.
    /// @param onBehalfOf The address that owns the NFT(s) and will receive the token amount.
    /// @param nftIds An array of the IDs of the NFTs to sell.
    /// @param liquidityPairs An array of the IDs of the liquidity pairs to use for the sale.
    /// @param minimumPrice The minimum acceptable price in tokens for the sale.
    /// @return finalPrice The final price in tokens received from the sale.
    function sell(
        address onBehalfOf,
        uint256[] calldata nftIds,
        uint256[] calldata liquidityPairs,
        uint256 minimumPrice
    )
        external
        override
        nonReentrant
        poolNotPaused
        returns (uint256 finalPrice)
    {
        require(nftIds.length == liquidityPairs.length, "TP:S:NFT_LP_MISMATCH");
        require(nftIds.length > 0, "TP:S:NFTS_0");

        // Only the swap router can call this function on behalf of another address
        if (onBehalfOf != msg.sender) {
            require(
                msg.sender == _addressProvider.getSwapRouter(),
                "TP:S:NOT_SWAP_ROUTER"
            );
        }

        uint256 totalProtocolFee;
        uint256 fee;
        DataTypes.LiquidityPair memory lp;
        uint256 lpIndex;
        uint256 protocolFeePercentage = ITradingPoolFactory(
            _addressProvider.getTradingPoolFactory()
        ).getProtocolFeePercentage();
        // Transfer the NFTs to the pool
        for (uint i = 0; i < nftIds.length; i++) {
            // Check if the LP exists
            lpIndex = liquidityPairs[i];
            require(_exists(lpIndex), "TP:S:LP_NOT_FOUND");

            // Get the LP details
            lp = _liquidityPairs[lpIndex];

            // Send NFT to the pool
            IERC721(_nft).safeTransferFrom(
                onBehalfOf,
                address(this),
                nftIds[i]
            );

            // Can't sell to sell LP
            require(lp.lpType != DataTypes.LPType.Sell, "TP:S:IS_SELL_LP");

            // Calculate the fee and protocol fee for the sale
            fee = PercentageMath.percentMul(lp.spotPrice, lp.fee);

            require(
                lp.tokenAmount >=
                    lp.spotPrice -
                        fee +
                        PercentageMath.percentMul(fee, protocolFeePercentage),
                "TP:S:INSUFFICIENT_TOKENS_IN_LP"
            );

            // Add nft to liquidity pair nft list
            _liquidityPairs[lpIndex].nftIds.push(nftIds[i]);

            //Update NFT tracker
            _nftToLp[nftIds[i]] = DataTypes.NftToLp({
                liquidityPair: SafeCast.toUint128(lpIndex),
                index: SafeCast.toUint128(
                    _liquidityPairs[lpIndex].nftIds.length - 1
                )
            });

            // Update token amount in liquidity pair
            _liquidityPairs[lpIndex].tokenAmount -= SafeCast.toUint128(
                (lp.spotPrice -
                    fee +
                    PercentageMath.percentMul(fee, protocolFeePercentage))
            );

            // Update total price quote and fee sum
            finalPrice += (lp.spotPrice - fee);
            totalProtocolFee += PercentageMath.percentMul(
                fee,
                protocolFeePercentage
            );

            // Update liquidity pair price
            if (lp.lpType != DataTypes.LPType.TradeUp) {
                _liquidityPairs[lpIndex].spotPrice = SafeCast.toUint128(
                    IPricingCurve(lp.curve).priceAfterSell(
                        lp.spotPrice,
                        lp.delta,
                        lp.fee
                    )
                );
            }
        }

        // Make sure the final price is greater than or equal to the minimum price set by the user
        require(finalPrice >= minimumPrice, "TP:S:MINIMUM_PRICE_NOT_REACHED");

        // Send tokens to user
        IERC20(_token).safeTransfer(msg.sender, finalPrice);

        // Send protocol fee to protocol fee distributor and call a checkpoint
        address feeDistributor = _addressProvider.getFeeDistributor();
        IERC20(_token).safeTransfer(feeDistributor, totalProtocolFee);
        IFeeDistributor(feeDistributor).checkpoint(_token);

        emit Sell(onBehalfOf, nftIds, finalPrice);
    }

    /// @notice Allows the owner of the contract to pause or unpause the contract.
    /// @param paused A boolean indicating whether to pause or unpause the contract.
    function setPause(bool paused) external onlyOwner {
        _paused = paused;
    }

    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 tokenId,
        uint256 batchSize
    ) internal override(ERC721Enumerable) {
        ERC721Enumerable._beforeTokenTransfer(from, to, tokenId, batchSize);
    }

    function supportsInterface(
        bytes4 interfaceId
    ) public view override(ERC165, ERC721Enumerable) returns (bool) {
        return
            type(ITradingPool).interfaceId == interfaceId ||
            ERC721Enumerable.supportsInterface(interfaceId) ||
            ERC165.supportsInterface(interfaceId);
    }

    function _requirePoolNotPaused() internal view {
        require(!_paused, "TP:POOL_PAUSED");
    }

    function _requireLpExists(uint256 lpIndex) internal view {
        require(_exists(lpIndex), "TP:LP_NOT_FOUND");
    }
}
