// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.8.17;

import {ITradingPool} from "../../interfaces/ITradingPool.sol";
import {IAddressesProvider} from "../../interfaces/IAddressesProvider.sol";
import {IPricingCurve} from "../../interfaces/IPricingCurve.sol";
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
        uint256 defaultSwapFee,
        string memory name,
        string memory symbol
    ) ERC721(name, symbol) {
        require(
            msg.sender == addressProvider.getTradingPoolFactory(),
            "Trading Pool must be created through Factory"
        );
        _addressProvider = addressProvider;
        _token = token;
        _nft = nft;
        _swapFee = defaultSwapFee;
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

    function addLiquidity(
        uint256 tokenAmount,
        uint256[] memory nftIds,
        address curve,
        uint256 delta,
        uint256 initialPrice
    ) external {
        // Require that the user is depositing something
        require(tokenAmount > 0 || nftIds.length > 0, "Deposit can't be empty");

        // Send user nfts to the pool
        for (uint i = 0; i < nftIds.length; i++) {
            IERC721(_nft).safeTransferFrom(
                msg.sender,
                address(this),
                nftIds[i]
            );
            _nftToLp[nftIds[i]] = DataTypes.NftToLp({
                liquidityPair: _lpCount,
                index: i
            });
        }

        // Send user token to the pool
        IERC20(_token).safeTransferFrom(msg.sender, address(this), tokenAmount);

        // Save the user deposit info
        _liquidityPairs[_lpCount] = DataTypes.LiquidityPair({
            nftIds: nftIds,
            tokenAmount: tokenAmount,
            curve: curve,
            delta: delta,
            price: initialPrice
        });

        // Mint liquidity position NFT
        ERC721._safeMint(msg.sender, _lpCount);

        emit AddLiquidity(
            msg.sender,
            _lpCount,
            nftIds,
            tokenAmount,
            curve,
            delta,
            initialPrice
        );

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
            delete _nftToLp[_liquidityPairs[lpId].nftIds[i]];
        }

        // Send user token to the pool
        IERC20(_token).safeTransfer(
            msg.sender,
            _liquidityPairs[lpId].tokenAmount
        );

        // delete the user deposit info
        delete _liquidityPairs[lpId];

        emit RemoveLiquidity(msg.sender, lpId);
    }

    function buy(uint256[] memory nftIds) external returns (uint256) {
        uint256 priceSum;
        uint256 priceAfterBuy;
        uint256 price;
        uint256 lpIndex;
        uint256 nftIndex;
        DataTypes.LiquidityPair memory lp;

        require(nftIds.length > 0, "Need to buy at least one NFT");

        for (uint i = 0; i < nftIds.length; i++) {
            lpIndex = _nftToLp[nftIds[i]].liquidityPair;
            nftIndex = _nftToLp[nftIds[i]].index;
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
            delete _nftToLp[nftIds[i]];

            // Send NFT to user
            IERC721(_nft).safeTransferFrom(
                address(this),
                msg.sender,
                nftIds[i]
            );
        }

        // Get tokens from user
        IERC20(_token).safeTransferFrom(msg.sender, address(this), priceSum);

        emit Buy(msg.sender, nftIds, priceSum);

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
        require(nftIds.length > 0, "Need to sell at least one NFT");
        uint256 priceSum;
        uint256 price;
        uint256 lpIndex;
        DataTypes.LiquidityPair memory lp;

        // Transfer the NFTs to the pool
        for (uint i = 0; i < nftIds.length; i++) {
            IERC721(_nft).safeTransferFrom(
                msg.sender,
                address(this),
                nftIds[i]
            );

            lpIndex = liquidityPairs[i];
            lp = _liquidityPairs[lpIndex];

            price =
                ((PercentageMath.PERCENTAGE_FACTOR - _swapFee) * lp.price) /
                PercentageMath.PERCENTAGE_FACTOR;
            priceSum += price;

            _liquidityPairs[lpIndex].nftIds.push(nftIds[i]);
            _liquidityPairs[lpIndex].tokenAmount -= price;
            _liquidityPairs[lpIndex].price = IPricingCurve(lp.curve)
                .priceAfterSell(lp.price, lp.delta);

            _nftToLp[nftIds[i]] = DataTypes.NftToLp({
                liquidityPair: lpIndex,
                index: _liquidityPairs[lpIndex].nftIds.length - 1
            });
        }

        IERC20(_token).safeTransfer(msg.sender, priceSum);

        emit Sell(msg.sender, nftIds, priceSum);

        return priceSum;
    }

    function setSwapFee(uint256 newSwapFee) external onlyOwner {
        _swapFee = newSwapFee;
    }

    function getSwapFee() external view returns (uint256) {
        return _swapFee;
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
