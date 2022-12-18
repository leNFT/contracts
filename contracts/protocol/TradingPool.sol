// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.8.17;

import {ITradingPool} from "../interfaces/ITradingPool.sol";
import {IAddressesProvider} from "../interfaces/IAddressesProvider.sol";
import {IPricingCurve} from "../interfaces/IPricingCurve.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Context} from "@openzeppelin/contracts/utils/Context.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {ERC721Enumerable} from "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import {ERC721Holder} from "@openzeppelin/contracts/token/ERC721/utils/ERC721Holder.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {DataTypes} from "../libraries/types/DataTypes.sol";
import {PercentageMath} from "../libraries/math/PercentageMath.sol";
import {IVotingEscrow} from "../interfaces/IVotingEscrow.sol";

contract TradingPool is
    Context,
    ERC721,
    ERC721Enumerable,
    ERC721Holder,
    ITradingPool,
    Ownable
{
    IAddressesProvider private _addressProvider;
    IERC20 private _token;
    address private _nft;
    uint256 private _swapFee;
    mapping(uint256 => DataTypes.LiquidityPair) _liquidityPairs;
    mapping(uint256 => DataTypes.NftToLiquidityPair) _nftToLiquidityPair;
    uint256 private _lpCount;

    using SafeERC20 for IERC20;

    modifier onlyMarket() {
        require(
            _msgSender() == _addressProvider.getMarket(),
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
            msg.sender == addressProvider.getMarket(),
            "Trading Pool must be created through Factory"
        );
        _addressProvider = addressProvider;
        _token = token;
        _nft = nft;
        _transferOwnership(owner);
    }

    function getLP(
        uint256 lpId
    ) external view returns (DataTypes.LiquidityPair memory) {
        return _liquidityPairs[lpId];
    }

    function addLiquidity(
        uint256 tokenAmount,
        uint256[] memory nftIds,
        address curve,
        uint256 delta,
        uint256 initialPrice
    ) external {
        // Send user nfts to the pool
        for (uint i = 0; i < nftIds.length; i++) {
            IERC721(_nft).safeTransferFrom(
                msg.sender,
                address(this),
                nftIds[i]
            );
            _nftToLiquidityPair[nftIds[i]] = DataTypes.NftToLiquidityPair({
                liquidityPair: _lpCount,
                index: i
            });
        }

        // Send user token to the pool
        IERC20(_token).safeTransferFrom(msg.sender, address(this), tokenAmount);

        // Save the user deposit info
        _liquidityPairs[_lpCount] = DataTypes.LiquidityPair({
            tokenAmount: tokenAmount,
            nftIds: nftIds,
            curve: curve,
            delta: delta,
            price: initialPrice
        });

        // Mint liquidity position NFT
        ERC721._safeMint(msg.sender, _lpCount);
        _lpCount++;
    }

    function removeLiquidity(uint256 lpId) external {
        // Burn liquidity position NFT
        ERC721._burn(lpId);

        // Send pool nfts to the user
        for (uint i = 0; i < _liquidityPairs[lpId].nftIds.length; i++) {
            IERC721(_nft).safeTransferFrom(
                address(this),
                msg.sender,
                _liquidityPairs[lpId].nftIds[i]
            );
        }

        // Send user token to the pool
        IERC20(_token).safeTransfer(
            address(this),
            _liquidityPairs[lpId].tokenAmount
        );

        // delete the user deposit info
        delete _liquidityPairs[lpId];
    }

    function buy(uint256[] memory nftIds) external returns (uint256) {
        uint256 priceSum;
        uint256 priceAfterBuy;
        uint256 price;
        uint256 lpIndex;
        uint256 nftIndex;
        DataTypes.LiquidityPair memory lp;

        for (uint i = 0; i < nftIds.length; i++) {
            lpIndex = _nftToLiquidityPair[nftIds[i]].liquidityPair;
            nftIndex = _nftToLiquidityPair[nftIds[i]].index;
            lp = _liquidityPairs[lpIndex];
            priceAfterBuy = IPricingCurve(lp.curve).priceAfterBuy(
                lp.price,
                lp.delta
            );
            price =
                ((PercentageMath.PERCENTAGE_FACTOR + _swapFee) *
                    priceAfterBuy) /
                PercentageMath.PERCENTAGE_FACTOR;

            // Update liquidity pair price
            _liquidityPairs[lpIndex].price = priceAfterBuy;

            // Remove nft from liquidity pair and add token swap amount
            _liquidityPairs[lpIndex].nftIds[nftIndex] = _liquidityPairs[lpIndex]
                .nftIds[_liquidityPairs[lpIndex].nftIds.length - 1];
            _liquidityPairs[lpIndex].nftIds.pop();
            _liquidityPairs[lpIndex].tokenAmount += price;

            // Increase total price sum
            priceSum += price;

            // Delete NFT from tracker
            delete _nftToLiquidityPair[nftIds[i]];

            // Send NFT to user
            IERC721(_nft).safeTransferFrom(
                address(this),
                msg.sender,
                nftIds[i]
            );
        }

        // Get tokens from user
        IERC20(_token).safeTransferFrom(msg.sender, address(this), priceSum);

        return priceSum;
    }

    function sell(
        uint256[] memory nftIds,
        uint256[] memory liquidityPairs
    ) external returns (uint256) {
        require(
            nftIds.length == liquidityPairs.length,
            "NFTs and Liquidity Pairs must have same length"
        );
        uint256 priceSum;
        uint256 price;
        uint256 lpIndex;
        uint256 nftIndex;
        DataTypes.LiquidityPair memory lp;

        // Transfer the NFTs to the pool
        for (uint i = 0; i < nftIds.length; i++) {
            IERC721(_nft).safeTransferFrom(
                msg.sender,
                address(this),
                nftIds[i]
            );

            lpIndex = _nftToLiquidityPair[nftIds[i]].liquidityPair;
            nftIndex = _nftToLiquidityPair[nftIds[i]].index;
            lp = _liquidityPairs[lpIndex];

            price =
                ((PercentageMath.PERCENTAGE_FACTOR - _swapFee) * lp.price) /
                PercentageMath.PERCENTAGE_FACTOR;
            priceSum += price;

            _liquidityPairs[nftIds[i]].nftIds.push(nftIds[i]);
            _liquidityPairs[lpIndex].tokenAmount -= price;
            _liquidityPairs[nftIds[i]].price = IPricingCurve(lp.curve)
                .priceAfterSell(lp.price, lp.delta);
        }

        IERC20(_token).safeTransfer(address(this), priceSum);

        return priceSum;
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
