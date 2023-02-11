// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.8.17;

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
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {DataTypes} from "../../libraries/types/DataTypes.sol";
import {PercentageMath} from "../../libraries/math/PercentageMath.sol";
import {IVotingEscrow} from "../../interfaces/IVotingEscrow.sol";
import "hardhat/console.sol";

contract TradingPool is
    Context,
    ERC721,
    ERC721Enumerable,
    ERC721Holder,
    ITradingPool,
    Ownable
{
    uint public constant MAX_FEE = 9000; // 90%

    IAddressesProvider private _addressProvider;
    bool internal _paused;
    IERC20 private _token;
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

    constructor(
        IAddressesProvider addressProvider,
        address owner,
        IERC20 token,
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

    function getNFT() external view returns (address) {
        return _nft;
    }

    function getToken() external view returns (address) {
        return address(_token);
    }

    function getLP(
        uint256 lpId
    ) external view returns (DataTypes.LiquidityPair memory) {
        return _liquidityPairs[lpId];
    }

    function nftToLp(uint256 nftId) external view returns (uint256) {
        return _nftToLp[nftId].liquidityPair;
    }

    function setLpFee(uint256 lpId, uint256 fee) external {
        //Require the caller owns LP
        require(_msgSender() == ERC721.ownerOf(lpId), "Must own LP position");

        _liquidityPairs[lpId].fee = fee;

        emit SetLpFee(msg.sender, lpId, fee);
    }

    function setLpSpotPrice(uint256 lpId, uint256 spotPrice) external {
        //Require the caller owns LP
        require(_msgSender() == ERC721.ownerOf(lpId), "Must own LP position");

        _liquidityPairs[lpId].spotPrice = spotPrice;

        emit SetLpSpotPrice(msg.sender, lpId, spotPrice);
    }

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

    function addLiquidity(
        address receiver,
        uint256[] memory nftIds,
        uint256 tokenAmount,
        uint256 spotPrice,
        address curve,
        uint256 delta,
        uint256 fee
    ) external {
        require(!_paused, "Pool is paused");

        // Check if pool will exceed maximum permitted amount
        require(
            tokenAmount + _token.balanceOf(address(this)) <
                ITradingPoolFactory(_addressProvider.getTradingPoolFactory())
                    .getTVLSafeguard(),
            "Trading pool exceeds safeguarded limit"
        );

        // Require that the user is depositing something
        require(tokenAmount > 0 || nftIds.length > 0, "Deposit can't be empty");

        // require that the curve is a valid curve
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
            nftIds,
            tokenAmount,
            spotPrice,
            curve,
            delta,
            fee
        );

        _lpCount++;
    }

    function removeLiquidity(uint256 lpId) public {
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

    function removeLiquidityBatch(uint256[] memory lpIds) external {
        require(!_paused, "Pool is paused");

        for (uint i = 0; i < lpIds.length; i++) {
            removeLiquidity(lpIds[i]);
        }
    }

    function buy(
        address onBehalfOf,
        uint256[] memory nftIds,
        uint256 maximumPrice
    ) external returns (uint256) {
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

            console.log("NFT To LP", _nftToLp[nftIds[i]].liquidityPair);

            // Delete NFT from tracker
            delete _nftToLp[nftIds[i]];

            // Send NFT to user
            console.log("Sending NFT to user", onBehalfOf);
            console.log("NFT ID", nftIds[i]);
            IERC721(_nft).safeTransferFrom(
                address(this),
                onBehalfOf,
                nftIds[i]
            );
        }

        finalPrice = priceQuote + totalFee;

        require(finalPrice <= maximumPrice, "Price higher than maximum price");

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
            address(_token)
        );

        emit Buy(_msgSender(), nftIds, finalPrice);

        return finalPrice;
    }

    function sell(
        address onBehalfOf,
        uint256[] memory nftIds,
        uint256[] memory liquidityPairs,
        uint256 minimumPrice
    ) external returns (uint256) {
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

        // Transfer the NFTs to the pool
        for (uint i = 0; i < nftIds.length; i++) {
            console.log("Transfering NFT %s to pool", nftIds[i]);
            IERC721(_nft).safeTransferFrom(
                onBehalfOf,
                address(this),
                nftIds[i]
            );

            uint256 lpIndex = liquidityPairs[i];
            lp = _liquidityPairs[lpIndex];
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

        require(finalPrice >= minimumPrice, "Price lower than minimum price");

        IERC20(_token).safeTransfer(_msgSender(), finalPrice);

        // Send protocol fee to protocol fee distributor
        IERC20(_token).safeTransfer(
            _addressProvider.getFeeDistributor(),
            (totalFee *
                ITradingPoolFactory(_addressProvider.getTradingPoolFactory())
                    .getProtocolFee()) / PercentageMath.PERCENTAGE_FACTOR
        );
        IFeeDistributor(_addressProvider.getFeeDistributor()).checkpoint(
            address(_token)
        );

        emit Sell(_msgSender(), nftIds, finalPrice);

        return finalPrice;
    }

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
