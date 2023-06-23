// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.8.19;

import {IWETH} from "../interfaces/IWETH.sol";
import {ILendingMarket} from "../interfaces/ILendingMarket.sol";
import {DataTypes} from "../libraries/types/DataTypes.sol";
import {ILoanCenter} from "../interfaces/ILoanCenter.sol";
import {IBribes} from "../interfaces/IBribes.sol";
import {ISwapRouter} from "../interfaces/ISwapRouter.sol";
import {ITradingPool} from "../interfaces/ITradingPool.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {Trustus} from "./Trustus/Trustus.sol";
import {IAddressProvider} from "../interfaces/IAddressProvider.sol";
import {ERC721Holder} from "@openzeppelin/contracts/token/ERC721/utils/ERC721Holder.sol";

/// @title WETHGateway Contract
/// @author leNFT
/// @notice This contract is the proxy for ETH interactions with the leNFT protocol
/// @dev Interacts with the WETH in order to wrap and unwrap ETH
contract WETHGateway is ERC721Holder {
    IAddressProvider private immutable _addressProvider;
    IWETH private immutable _weth;

    modifier lendingPoolETH(address lendingPool) {
        _requireLendingPoolETH(lendingPool);
        _;
    }

    modifier loanPoolETH(uint256 loanId) {
        _requireLoanPoolETH(loanId);
        _;
    }

    modifier tradingPoolETH(address tradingPool) {
        _requireTradingPoolETH(tradingPool);
        _;
    }

    /// @notice Constructor for the WETHGateway contract
    /// @param addressProvider The address of the addressProvider contract
    /// @param weth The address of the WETH contract
    constructor(IAddressProvider addressProvider, IWETH weth) {
        _addressProvider = addressProvider;
        _weth = weth;
    }

    /// @notice Deposit ETH in a wETH lending pool
    /// @param lendingPool Lending pool to deposit into
    function depositLendingPool(
        address lendingPool
    ) external payable lendingPoolETH(lendingPool) {
        IWETH weth = _weth;
        // Deposit and approve WETH
        weth.deposit{value: msg.value}();
        weth.approve(lendingPool, msg.value);

        IERC4626(lendingPool).deposit(msg.value, msg.sender);
    }

    /// @notice Withdraw ETH from a WETH lending pool
    /// @param lendingPool Lending pool to withdraw from
    /// @param amount Amount of ETH to be withdrawn
    function withdrawLendingPool(
        address lendingPool,
        uint256 amount
    ) external lendingPoolETH(lendingPool) {
        IERC4626(lendingPool).withdraw(amount, address(this), msg.sender);
        _weth.withdraw(amount);

        (bool sent, ) = msg.sender.call{value: amount}("");
        require(sent, "ETHG:WLP:ETH_TRANSFER_FAILED");
    }

    /// @notice Borrow ETH from a WETH lending pool while an NFT as collateral
    /// @dev NFT approval needs to be given to the LoanCenter contract
    /// @param amount Amount of ETH to be borrowed
    /// @param nftAddress Address of the NFT collateral
    /// @param nftTokenIds Token ids of the NFT(s) collateral
    /// @param genesisNFTId Token id of the genesis NFT to be used for the loan (0 if none)
    /// @param request ID of the collateral price request sent by the trusted server
    /// @param packet Signed collateral price request sent by the trusted server
    function borrow(
        uint256 amount,
        address nftAddress,
        uint256[] calldata nftTokenIds,
        uint256 genesisNFTId,
        bytes32 request,
        Trustus.TrustusPacket calldata packet
    ) external {
        ILendingMarket market = ILendingMarket(
            _addressProvider.getLendingMarket()
        );

        // Transfer the collateral to the WETH Gateway
        for (uint256 i = 0; i < nftTokenIds.length; i++) {
            IERC721(nftAddress).safeTransferFrom(
                msg.sender,
                address(this),
                nftTokenIds[i]
            );

            // Approve the collateral to be moved by the market
            IERC721(nftAddress).approve(address(market), nftTokenIds[i]);
        }

        // SLOAD the WETH address to save gas
        IWETH weth = _weth;

        market.borrow(
            msg.sender,
            address(weth),
            amount,
            nftAddress,
            nftTokenIds,
            genesisNFTId,
            request,
            packet
        );

        weth.withdraw(amount);

        (bool sent, ) = msg.sender.call{value: amount}("");
        require(sent, "ETHG:B:ETH_TRANSFER_FAILED");
    }

    /// @notice Repay an an active loan with ETH
    /// @param loanId The ID of the loan to be paid
    function repay(uint256 loanId) external payable {
        ILoanCenter loanCenter = ILoanCenter(_addressProvider.getLoanCenter());
        address pool = loanCenter.getLoanLendingPool(loanId);

        ILendingMarket market = ILendingMarket(
            _addressProvider.getLendingMarket()
        );

        // SLOAD the WETH address to save gas
        IWETH weth = _weth;

        require(
            IERC4626(pool).asset() == address(weth),
            "ETHG:R:UNDERLYING_NOT_WETH"
        );

        // If we are repaying an auctioned loan we also need to pay the auctineer fee
        uint256 auctioneerFee;
        if (loanCenter.getLoanState(loanId) == DataTypes.LoanState.Auctioned) {
            auctioneerFee = loanCenter.getLoanAuctioneerFee(loanId);
            require(auctioneerFee < msg.value, "ETHG:R:NO_AUCTIONEER_FEE");
            weth.approve(address(market), auctioneerFee);
        }

        // Deposit and approve WETH
        weth.deposit{value: msg.value}();
        weth.approve(pool, msg.value - auctioneerFee);

        // Repay loan
        market.repay(loanId, msg.value - auctioneerFee);
    }

    /// @notice Deposit ETH and/or NFTs into a trading pool to provide liquidity
    /// @param pool The trading pool address
    /// @param lpType The type of LP
    /// @param nftIds Token ids of the NFTs to deposit
    /// @param initialPrice The initial price of the liquidity provider tokens
    /// @param curve The curve used to calculate the price of the LP tokens
    /// @param delta The minimum price change to update the curve
    /// @param fee The fee charged on trades in the pool
    function depositTradingPool(
        address pool,
        DataTypes.LPType lpType,
        uint256[] calldata nftIds,
        uint256 initialPrice,
        address curve,
        uint256 delta,
        uint256 fee
    ) external payable tradingPoolETH(pool) {
        // Transfer the NFTs to the WETH Gateway and approve them for use
        IERC721 tradingPoolNFT = IERC721(ITradingPool(pool).getNFT());
        if (nftIds.length > 0) {
            for (uint i = 0; i < nftIds.length; i++) {
                tradingPoolNFT.safeTransferFrom(
                    msg.sender,
                    address(this),
                    nftIds[i]
                );
            }
            tradingPoolNFT.setApprovalForAll(pool, true);
        }

        // Deposit and approve WETH
        if (msg.value > 0) {
            // SLOAD the WETH address to save gas
            IWETH weth = _weth;

            weth.deposit{value: msg.value}();
            weth.approve(pool, msg.value);
        }

        ITradingPool(pool).addLiquidity(
            msg.sender,
            lpType,
            nftIds,
            msg.value,
            initialPrice,
            curve,
            delta,
            fee
        );
    }

    /// @notice Withdraw liquidity from a trading pool
    /// @param pool The trading pool address
    /// @param lpId The ID of the liquidity provider tokens to withdraw
    function withdrawTradingPool(
        address pool,
        uint256 lpId
    ) external tradingPoolETH(pool) {
        // Send LP NFT to this contract
        IERC721(pool).safeTransferFrom(msg.sender, address(this), lpId);

        // Get LP info so we can send the correct amounts back
        DataTypes.LiquidityPair memory lp = ITradingPool(pool).getLP(lpId);

        // Remove liquidity
        ITradingPool(pool).removeLiquidity(lpId);

        // Send NFTs back to the user
        IERC721 tradingPoolNFT = IERC721(ITradingPool(pool).getNFT());
        for (uint i = 0; i < lp.nftIds.length; i++) {
            tradingPoolNFT.safeTransferFrom(
                address(this),
                msg.sender,
                lp.nftIds[i]
            );
        }

        // Send ETH back to the user
        _weth.withdraw(lp.tokenAmount);

        (bool sent, ) = msg.sender.call{value: lp.tokenAmount}("");
        require(sent, "ETHG:WTP:ETH_TRANSFER_FAILED");
    }

    /// @notice Withdraws liquidity from a trading pool for a batch of liquidity pairs.
    /// @param pool The address of the trading pool.
    /// @param lpIds The array of liquidity pair ids to withdraw.
    function withdrawBatchTradingPool(
        address pool,
        uint256[] calldata lpIds
    ) external tradingPoolETH(pool) {
        uint256 totalAmount;
        uint256[][] memory nftIds = new uint256[][](lpIds.length);

        // Send LP NFTs to this contract
        for (uint i = 0; i < lpIds.length; i++) {
            IERC721(pool).safeTransferFrom(msg.sender, address(this), lpIds[i]);

            // Get LP info so we can send the correct amounts back
            DataTypes.LiquidityPair memory lp = ITradingPool(pool).getLP(
                lpIds[i]
            );

            // Add up the total amount of ETH to withdraw
            totalAmount += lp.tokenAmount;

            // Add up the total amount of NFTs to withdraw
            nftIds[i] = lp.nftIds;
        }

        // Remove liquidity in batch
        ITradingPool(pool).removeLiquidityBatch(lpIds);

        // Send NFTs back to the user
        IERC721 tradingPoolNFT = IERC721(ITradingPool(pool).getNFT());
        for (uint a = 0; a < nftIds.length; a++) {
            for (uint b = 0; b < nftIds[a].length; b++) {
                tradingPoolNFT.safeTransferFrom(
                    address(this),
                    msg.sender,
                    nftIds[a][b]
                );
            }
        }

        // Send ETH back to the user
        _weth.withdraw(totalAmount);

        (bool sent, ) = msg.sender.call{value: totalAmount}("");
        require(sent, "ETHG:WBTP:ETH_TRANSFER_FAILED");
    }

    /// @notice Buys NFT from a trading pool by depositing WETH and specifying the NFT ids and maximum price to pay.
    /// @param pool The address of the trading pool.
    /// @param nftIds The array of NFT ids to buy.
    /// @param maximumPrice The maximum amount of ETH to pay for the purchase.
    function buy(
        address pool,
        uint256[] calldata nftIds,
        uint256 maximumPrice
    ) external payable tradingPoolETH(pool) {
        require(msg.value == maximumPrice, "ETHG:B:VALUE_NOT_MAXIMUM_PRICE");

        // SLOAD the WETH address to save gas
        IWETH weth = _weth;

        // Deposit and approve WETH
        weth.deposit{value: msg.value}();
        weth.approve(pool, msg.value);

        uint256 finalPrice = ITradingPool(pool).buy(
            msg.sender,
            nftIds,
            maximumPrice
        );

        // Send ETH back to the user
        if (msg.value > finalPrice) {
            weth.withdraw(msg.value - finalPrice);

            (bool sent, ) = msg.sender.call{value: msg.value - finalPrice}("");
            require(sent, "ETHG:B:ETH_TRANSFER_FAILED");
        }
    }

    /// @notice Sells NFTs against a pool's liquidity pairs, specifying the NFT ids, liquidity pairs, and minimum price expected.
    /// @param pool The address of the trading pool.
    /// @param nftIds The array of NFT ids to sell.
    /// @param liquidityPairs The array of liquidity pair to sell the NFTs against.
    /// @param minimumPrice The minimum amount of ETH to receive for the sale.
    function sell(
        address pool,
        uint256[] calldata nftIds,
        uint256[] calldata liquidityPairs,
        uint256 minimumPrice
    ) external tradingPoolETH(pool) {
        // Send NFTs to this contract and approve them for pool use
        IERC721 tradingPoolNFT = IERC721(ITradingPool(pool).getNFT());
        for (uint i = 0; i < nftIds.length; i++) {
            tradingPoolNFT.safeTransferFrom(
                msg.sender,
                address(this),
                nftIds[i]
            );
        }
        tradingPoolNFT.setApprovalForAll(pool, true);

        // Sell NFTs
        uint256 finalPrice = ITradingPool(pool).sell(
            address(this),
            nftIds,
            liquidityPairs,
            minimumPrice
        );

        // Send ETH back to the user
        _weth.withdraw(finalPrice);

        (bool sent, ) = msg.sender.call{value: finalPrice}("");
        require(sent, "ETHG:S:ETH_TRANSFER_FAILED");
    }

    /// @notice Swaps NFTs between two trading pools, with one pool acting as the buyer and the other as the seller.
    /// @param buyPool The address of the buying trading pool.
    /// @param sellPool The address of the selling trading pool.
    /// @param buyNftIds The array of NFT ids to buy.
    /// @param maximumBuyPrice The maximum amount of ETH to pay for the purchase.
    /// @param sellNftIds The array of NFT ids to sell.
    /// @param sellLps The array of liquidity pair to sell the NFTs against.
    /// @param minimumSellPrice The minimum amount of ETH to receive for the sale.
    function swap(
        address buyPool,
        address sellPool,
        uint256[] calldata buyNftIds,
        uint256 maximumBuyPrice,
        uint256[] calldata sellNftIds,
        uint256[] calldata sellLps,
        uint256 minimumSellPrice
    ) external payable {
        // SLOAD the WETH address to save gas
        IWETH weth = _weth;

        require(
            ITradingPool(buyPool).getToken() == address(weth),
            "ETHG:S:BUY_UNDERLYING_NOT_WETH"
        );
        require(
            ITradingPool(sellPool).getToken() == address(weth),
            "ETHG:S:SELL_UNDERLYING_NOT_WETH"
        );
        // Make sure the msg.value covers the swap
        if (maximumBuyPrice > minimumSellPrice) {
            require(
                msg.value == maximumBuyPrice - minimumSellPrice,
                "ETHG:S:INVALID_VALUE"
            );

            // Deposit and approve WETH
            weth.deposit{value: msg.value}();
            weth.approve(_addressProvider.getSwapRouter(), msg.value);
        }

        // avoid stack too deep
        {
            // Send NFTs to this contract and approve them for pool use
            IERC721 sellPoolNFT = IERC721(ITradingPool(sellPool).getNFT());
            for (uint i = 0; i < sellNftIds.length; i++) {
                sellPoolNFT.safeTransferFrom(
                    msg.sender,
                    address(this),
                    sellNftIds[i]
                );
            }
            sellPoolNFT.setApprovalForAll(sellPool, true);
        }

        // Swap
        uint256 returnedAmount = ISwapRouter(_addressProvider.getSwapRouter())
            .swap(
                buyPool,
                sellPool,
                buyNftIds,
                maximumBuyPrice,
                sellNftIds,
                sellLps,
                minimumSellPrice
            );

        // Send NFTs back to the user
        IERC721 buyPoolNFT = IERC721(ITradingPool(buyPool).getNFT());
        for (uint i = 0; i < buyNftIds.length; i++) {
            buyPoolNFT.safeTransferFrom(
                address(this),
                msg.sender,
                buyNftIds[i]
            );
        }

        // Send ETH back to the user
        if (returnedAmount > 0) {
            weth.withdraw(returnedAmount);
            (bool sent, ) = msg.sender.call{value: returnedAmount}("");
            require(sent, "ETHG:S:ETH_TRANSFER_FAILED");
        }
    }

    /// @notice Deposits ETH into the bribe contract to be used for bribing.
    /// @dev Bribe is applied to the next epoch
    /// @param gauge The address of the gauge to bribe.
    function depositBribe(address gauge) external payable {
        address bribes = _addressProvider.getBribes();
        // SLOAD the WETH address to save gas
        IWETH weth = _weth;
        weth.deposit{value: msg.value}();
        weth.approve(bribes, msg.value);
        IBribes(bribes).depositBribe(
            msg.sender,
            address(weth),
            gauge,
            msg.value
        );
    }

    /// @notice Liquidates a loan.
    /// @param loanId The id of the loan to liquidate.
    /// @param request The request id of the loan to liquidate.
    /// @param packet The Trustus packet of the loan to liquidate.
    function createLiquidationAuction(
        uint256 loanId,
        bytes32 request,
        Trustus.TrustusPacket calldata packet
    ) external payable loanPoolETH(loanId) {
        address lendingMarket = _addressProvider.getLendingMarket();
        // SLOAD the WETH address to save gas
        IWETH weth = _weth;
        // Deposit and approve WETH
        weth.deposit{value: msg.value}();
        weth.approve(lendingMarket, msg.value);

        // Create auction
        ILendingMarket(lendingMarket).createLiquidationAuction(
            msg.sender,
            loanId,
            msg.value,
            request,
            packet
        );
    }

    /// @notice Bids on a liquidation auction.
    /// @param loanId The id of the loan to bid on.
    function bidLiquidationAuction(
        uint256 loanId
    ) external payable loanPoolETH(loanId) {
        address lendingMarket = _addressProvider.getLendingMarket();
        // SLOAD the WETH address to save gas
        IWETH weth = _weth;
        // Deposit and approve WETH
        weth.deposit{value: msg.value}();
        weth.approve(lendingMarket, msg.value);

        // Bid on auction
        ILendingMarket(lendingMarket).bidLiquidationAuction(
            msg.sender,
            loanId,
            msg.value
        );
    }

    function _requireLendingPoolETH(address lendingPool) internal view {
        require(
            IERC4626(lendingPool).asset() == address(_weth),
            "ETHG:UNDERLYING_NOT_WETH"
        );
    }

    function _requireLoanPoolETH(uint256 loanId) internal view {
        // Make sure the loan pool asset is WETH
        require(
            IERC4626(
                ILoanCenter(_addressProvider.getLoanCenter())
                    .getLoanLendingPool(loanId)
            ).asset() == address(_weth),
            "ETHG:UNDERLYING_NOT_WETH"
        );
    }

    function _requireTradingPoolETH(address tradingPool) internal view {
        require(
            ITradingPool(tradingPool).getToken() == address(_weth),
            "ETHG:UNDERLYING_NOT_WETH"
        );
    }

    // Receive ETH function: Intended to receive ETH from WETH contract
    receive() external payable {
        require(msg.sender == address(_weth), "ETHG:RECEIVE:NOT_WETH");
    }

    /**
     * @dev Revert fallback calls
     */
    fallback() external payable {
        revert("ETHG:F:INVALID_CALL");
    }
}
