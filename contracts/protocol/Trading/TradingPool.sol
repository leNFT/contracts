// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.8.19;

import {ITradingPool} from "../../interfaces/ITradingPool.sol";
import {IAddressesProvider} from "../../interfaces/IAddressesProvider.sol";
import {IPricingCurve} from "../../interfaces/IPricingCurve.sol";
import {IFeeDistributor} from "../../interfaces/IFeeDistributor.sol";
import {ITradingPoolFactory} from "../../interfaces/ITradingPoolFactory.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Context} from "@openzeppelin/contracts/utils/Context.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {ERC721Enumerable} from "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import {ERC721Holder} from "@openzeppelin/contracts/token/ERC721/utils/ERC721Holder.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {DataTypes} from "../../libraries/types/DataTypes.sol";
import {PercentageMath} from "../../libraries/math/PercentageMath.sol";
import {IVotingEscrow} from "../../interfaces/IVotingEscrow.sol";
import {ILiquidityPairMetadata} from "../../interfaces/ILiquidityPairMetadata.sol";
import "hardhat/console.sol";

/// @title Trading Pool Contract
/// @notice A contract that enables the creation of liquidity pools and the trading of NFTs and ERC20 tokens.
/// @dev This contract manages liquidity pairs, each consisting of a set of NFTs and an ERC20 token, as well as the trading of these pairs.
contract TradingPool is
    Context,
    ERC721,
    ERC721Enumerable,
    ERC721Holder,
    ITradingPool,
    Ownable,
    ReentrancyGuard
{
    uint public constant MAX_FEE = 9000; // 90%

    IAddressesProvider private _addressProvider;
    bool internal _paused;
    address private _token;
    address private _nft;
    mapping(uint256 => DataTypes.LiquidityPair) _liquidityPairs;
    mapping(uint256 => DataTypes.NftToLp) _nftToLp;
    uint256 private _lpCount;

    using SafeERC20 for IERC20;

    modifier onlyMarket() {
        require(
            _msgSender() == _addressProvider.getLendingMarket(),
            "Callers must be Market contract"
        );
        _;
    }

    /// @notice Trading Pool constructor.
    /// @param addressProvider The address provider contract.
    /// @param owner The owner of the Trading Pool contract.
    /// @param token The ERC20 token used in the trading pool.
    /// @param nft The address of the ERC721 contract.
    /// @param name The name of the ERC721 token.
    /// @param symbol The symbol of the ERC721 token.
    /// @notice The constructor should only be called by the Trading Pool
    constructor(
        IAddressesProvider addressProvider,
        address owner,
        address token,
        address nft,
        string memory name,
        string memory symbol
    ) ERC721(name, symbol) {
        require(
            _msgSender() == addressProvider.getTradingPoolFactory(),
            "Trading Pool must be created through Factory"
        );
        _addressProvider = addressProvider;
        _token = token;
        _nft = nft;
        _transferOwnership(owner);
    }

    function tokenURI(
        uint256 tokenId
    ) public view override returns (string memory) {
        return
            ILiquidityPairMetadata(_addressProvider.getLiquidityPairMetadata())
                .tokenURI(address(this), tokenId);
    }

    /// @notice Gets the address of the ERC721 traded in the pool.
    /// @return The address of the ERC721 token.
    function getNFT() external view returns (address) {
        return _nft;
    }

    /// @notice Gets the address of the ERC20 token traded in the pool.
    /// @return The address of the ERC20 token.
    function getToken() external view returns (address) {
        return _token;
    }

    /// @notice Gets the liquidity pair with the specified ID.
    /// @param lpId The ID of the liquidity pair.
    /// @return The liquidity pair.
    function getLP(
        uint256 lpId
    ) external view returns (DataTypes.LiquidityPair memory) {
        return _liquidityPairs[lpId];
    }

    /// @notice Gets the ID of the liquidity pair associated with the specified NFT.
    /// @param nftId The ID of the NFT.
    /// @return The ID of the liquidity pair.
    function nftToLp(uint256 nftId) external view returns (uint256) {
        return _nftToLp[nftId].liquidityPair;
    }

    /// @notice Sets the fee for the specified liquidity pair.
    /// @dev The caller must own the liquidity pair.
    /// @param lpId The ID of the liquidity pair.
    /// @param fee The new fee.
    function setLpFee(uint256 lpId, uint256 fee) external {
        //Require the caller owns LP
        require(_msgSender() == ERC721.ownerOf(lpId), "Must own LP position");

        _liquidityPairs[lpId].fee = fee;

        emit SetLpFee(msg.sender, lpId, fee);
    }

    /// @notice Sets the spot price for the specified liquidity pair.
    /// @dev The caller must own the liquidity pair.
    /// @param lpId The ID of the liquidity pair.
    /// @param spotPrice The new spot price.
    function setLpSpotPrice(uint256 lpId, uint256 spotPrice) external {
        //Require the caller owns LP
        require(_msgSender() == ERC721.ownerOf(lpId), "Must own LP position");

        _liquidityPairs[lpId].spotPrice = spotPrice;

        emit SetLpSpotPrice(msg.sender, lpId, spotPrice);
    }

    /// @notice The caller must own the liquidity pair.
    /// @dev Sets the pricing curve for the specified liquidity pair.
    /// @param lpId The ID of the liquidity pair.
    /// @param curve The new pricing curve.
    /// @param delta The new delta.
    function setLpPricingCurve(
        uint256 lpId,
        address curve,
        uint256 delta
    ) external {
        //Require the caller owns LP
        require(_msgSender() == ERC721.ownerOf(lpId), "Must own LP position");

        _liquidityPairs[lpId].curve = curve;
        _liquidityPairs[lpId].delta = delta;

        emit SetLpPricingCurve(msg.sender, lpId, curve, delta);
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
    ) external nonReentrant {
        require(!_paused, "Pool is paused");

        // Check if pool will exceed maximum permitted amount
        require(
            tokenAmount + IERC20(_token).balanceOf(address(this)) <
                ITradingPoolFactory(_addressProvider.getTradingPoolFactory())
                    .getTVLSafeguard(),
            "Trading pool exceeds safeguarded limit"
        );

        // Require that the user is depositing something
        if (lpType == DataTypes.LPType.Trade) {
            require(
                tokenAmount > 0 || nftIds.length > 0,
                "Deposit can't be empty"
            );
        } else if (lpType == DataTypes.LPType.Buy) {
            require(
                tokenAmount > 0 && nftIds.length == 0,
                "Deposit should only contain tokens"
            );
        } else if (lpType == DataTypes.LPType.Sell) {
            require(
                nftIds.length > 0 && tokenAmount == 0,
                "Deposit should only contain NFTs"
            );
        }

        // Require that the curve conforms to the curve interface
        require(
            IERC165(curve).supportsInterface(type(IPricingCurve).interfaceId),
            "Curve must be a valid curve contract"
        );

        // Validate delta
        require(IPricingCurve(curve).validateDelta(delta), "Invalid delta");

        // Validate spot price
        require(
            IPricingCurve(curve).validateSpotPrice(spotPrice),
            "Invalid spot price"
        );

        // require that the fee is less than 90%
        require(fee <= MAX_FEE, "Fee must be less than 90%");

        // Send user nfts to the pool
        for (uint i = 0; i < nftIds.length; i++) {
            IERC721(_nft).safeTransferFrom(
                _msgSender(),
                address(this),
                nftIds[i]
            );
            _nftToLp[nftIds[i]] = DataTypes.NftToLp({
                liquidityPair: _lpCount,
                index: i
            });
        }

        // Send user token to the pool
        IERC20(_token).safeTransferFrom(
            _msgSender(),
            address(this),
            tokenAmount
        );

        // Save the user deposit info
        _liquidityPairs[_lpCount] = DataTypes.LiquidityPair({
            lpType: lpType,
            nftIds: nftIds,
            tokenAmount: tokenAmount,
            spotPrice: spotPrice,
            curve: curve,
            delta: delta,
            fee: fee
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

    /// @notice Removes liquidity, sending back deposited tokens and transferring the NFTs to the user
    /// @param lpId The ID of the LP token to remove
    function removeLiquidity(uint256 lpId) public nonReentrant {
        require(!_paused, "Pool is paused");

        //Require the caller owns LP
        require(_msgSender() == ERC721.ownerOf(lpId), "Must own LP position");

        // Send pool nfts to the user
        for (uint i = 0; i < _liquidityPairs[lpId].nftIds.length; i++) {
            IERC721(_nft).safeTransferFrom(
                address(this),
                _msgSender(),
                _liquidityPairs[lpId].nftIds[i]
            );
            delete _nftToLp[_liquidityPairs[lpId].nftIds[i]];
        }

        // Send pool token back to user
        IERC20(_token).safeTransfer(
            _msgSender(),
            _liquidityPairs[lpId].tokenAmount
        );

        // delete the user deposit info
        delete _liquidityPairs[lpId];

        // Burn liquidity position NFT
        ERC721._burn(lpId);

        emit RemoveLiquidity(_msgSender(), lpId);
    }

    /// @notice Removes liquidity in batches by calling the removeLiquidity function for each LP token ID in the lpIds array
    /// @param lpIds The IDs of the LP tokens to remove liquidity from
    function removeLiquidityBatch(uint256[] calldata lpIds) external {
        require(!_paused, "Pool is paused");

        for (uint i = 0; i < lpIds.length; i++) {
            removeLiquidity(lpIds[i]);
        }
    }

    /// @notice Buys NFTs and deposits them into the pool in exchange for pool tokens
    /// @dev Buys NFTs and deposits them into the pool in exchange for pool tokens
    /// @param onBehalfOf The address to deposit the NFTs to
    /// @param nftIds The IDs of the NFTs to buy
    /// @param maximumPrice The maximum price the user is willing to pay for the NFTs
    /// @return The final price paid for the NFTs
    function buy(
        address onBehalfOf,
        uint256[] calldata nftIds,
        uint256 maximumPrice
    ) external nonReentrant returns (uint256) {
        require(!_paused, "Pool is paused");

        require(nftIds.length > 0, "Need to buy at least one NFT");

        uint256 priceQuote;
        uint256 finalPrice;
        uint256 lpIndex;
        uint256 fee;
        uint256 totalFee;
        uint256 protocolFee;
        DataTypes.LiquidityPair memory lp;

        for (uint i = 0; i < nftIds.length; i++) {
            lpIndex = _nftToLp[nftIds[i]].liquidityPair;
            lp = _liquidityPairs[lpIndex];

            // Can't buy from buy LP
            require(lp.lpType != DataTypes.LPType.Buy, "Can't buy from buy LP");

            fee = (lp.spotPrice * lp.fee) / PercentageMath.PERCENTAGE_FACTOR;
            protocolFee =
                (fee *
                    ITradingPoolFactory(
                        _addressProvider.getTradingPoolFactory()
                    ).getProtocolFee()) /
                PercentageMath.PERCENTAGE_FACTOR;

            // Remove nft from liquidity pair and add token swap amount
            _liquidityPairs[lpIndex].nftIds[
                _nftToLp[nftIds[i]].index
            ] = _liquidityPairs[lpIndex].nftIds[
                _liquidityPairs[lpIndex].nftIds.length - 1
            ];
            _liquidityPairs[lpIndex].nftIds.pop();
            _liquidityPairs[lpIndex].tokenAmount +=
                lp.spotPrice +
                fee -
                protocolFee;

            // Increase total price and fee sum
            priceQuote += lp.spotPrice;
            totalFee += fee;

            // Update liquidity pair price
            _liquidityPairs[lpIndex].spotPrice = IPricingCurve(lp.curve)
                .priceAfterBuy(lp.spotPrice, lp.delta);

            // Delete NFT from tracker
            delete _nftToLp[nftIds[i]];

            // Send NFT to user
            IERC721(_nft).safeTransferFrom(
                address(this),
                onBehalfOf,
                nftIds[i]
            );
        }

        finalPrice = priceQuote + totalFee;

        require(
            finalPrice <= maximumPrice,
            "Price higher than maximum price set by caller"
        );

        // Get tokens from user
        IERC20(_token).safeTransferFrom(
            _msgSender(),
            address(this),
            finalPrice
        );

        // Send protocol fee to protocol fee distributor
        IERC20(_token).safeTransfer(
            _addressProvider.getFeeDistributor(),
            (totalFee *
                ITradingPoolFactory(_addressProvider.getTradingPoolFactory())
                    .getProtocolFee()) / PercentageMath.PERCENTAGE_FACTOR
        );
        IFeeDistributor(_addressProvider.getFeeDistributor()).checkpoint(
            _token
        );

        emit Buy(_msgSender(), nftIds, finalPrice);

        return finalPrice;
    }

    /// @notice Allows an address to sell one or more NFTs in exchange for a token amount.
    /// @param onBehalfOf The address that owns the NFT(s) and will receive the token amount.
    /// @param nftIds An array of the IDs of the NFTs to sell.
    /// @param liquidityPairs An array of the IDs of the liquidity pairs to use for the sale.
    /// @param minimumPrice The minimum acceptable price in tokens for the sale.
    /// @return The final price in tokens received from the sale.
    function sell(
        address onBehalfOf,
        uint256[] calldata nftIds,
        uint256[] calldata liquidityPairs,
        uint256 minimumPrice
    ) external nonReentrant returns (uint256) {
        require(!_paused, "Pool is paused");

        require(
            nftIds.length == liquidityPairs.length,
            "NFTs and Liquidity Pairs must have same length"
        );
        require(nftIds.length > 0, "Need to sell at least one NFT");
        if (onBehalfOf != _msgSender()) {
            require(
                _msgSender() == _addressProvider.getSwapRouter(),
                "Only SwapRouter can sell on behalf of another address"
            );
        }
        uint256 priceQuote;
        uint256 fee;
        uint256 totalFee;
        uint256 finalPrice;
        uint256 protocolFee;
        DataTypes.LiquidityPair memory lp;
        uint256 lpIndex;

        // Transfer the NFTs to the pool
        for (uint i = 0; i < nftIds.length; i++) {
            IERC721(_nft).safeTransferFrom(
                onBehalfOf,
                address(this),
                nftIds[i]
            );

            lpIndex = liquidityPairs[i];
            lp = _liquidityPairs[lpIndex];

            // Can't sell to sell LP
            require(
                lp.lpType != DataTypes.LPType.Sell,
                "Can't sell to sell LP"
            );

            fee = (lp.spotPrice * lp.fee) / PercentageMath.PERCENTAGE_FACTOR;
            protocolFee =
                (fee *
                    ITradingPoolFactory(
                        _addressProvider.getTradingPoolFactory()
                    ).getProtocolFee()) /
                PercentageMath.PERCENTAGE_FACTOR;

            // Update total price quote and fee sum
            priceQuote += lp.spotPrice;
            totalFee += fee;

            _liquidityPairs[lpIndex].nftIds.push(nftIds[i]);
            _liquidityPairs[lpIndex].tokenAmount -=
                lp.spotPrice -
                fee +
                protocolFee;
            _liquidityPairs[lpIndex].spotPrice = IPricingCurve(lp.curve)
                .priceAfterSell(lp.spotPrice, lp.delta);

            _nftToLp[nftIds[i]] = DataTypes.NftToLp({
                liquidityPair: lpIndex,
                index: _liquidityPairs[lpIndex].nftIds.length - 1
            });
        }

        finalPrice = priceQuote - totalFee;

        require(
            finalPrice >= minimumPrice,
            "Price lower than minimum price set by caller"
        );

        IERC20(_token).safeTransfer(_msgSender(), finalPrice);

        // Send protocol fee to protocol fee distributor
        IERC20(_token).safeTransfer(
            _addressProvider.getFeeDistributor(),
            (totalFee *
                ITradingPoolFactory(_addressProvider.getTradingPoolFactory())
                    .getProtocolFee()) / PercentageMath.PERCENTAGE_FACTOR
        );
        IFeeDistributor(_addressProvider.getFeeDistributor()).checkpoint(
            _token
        );

        emit Sell(_msgSender(), nftIds, finalPrice);

        return finalPrice;
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
    ) internal override(ERC721, ERC721Enumerable) {
        ERC721Enumerable._beforeTokenTransfer(from, to, tokenId, batchSize);
    }

    function supportsInterface(
        bytes4 interfaceId
    ) public view override(ERC721, ERC721Enumerable, IERC165) returns (bool) {
        return ERC721Enumerable.supportsInterface(interfaceId);
    }
}
