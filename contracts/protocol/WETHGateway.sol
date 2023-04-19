// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.8.19;

import {IWETH} from "../interfaces/IWETH.sol";
import {ILendingMarket} from "../interfaces/ILendingMarket.sol";
import {ILendingMarket} from "../interfaces/ILendingMarket.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {IERC721Receiver} from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import {DataTypes} from "../libraries/types/DataTypes.sol";
import {ILoanCenter} from "../interfaces/ILoanCenter.sol";
import {ISwapRouter} from "../interfaces/ISwapRouter.sol";
import {ITradingPool} from "../interfaces/ITradingPool.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {Trustus} from "./Trustus/Trustus.sol";
import {Context} from "@openzeppelin/contracts/utils/Context.sol";
import {IAddressesProvider} from "../interfaces/IAddressesProvider.sol";

/// @title WETHGateway Contract
/// @author leNFT
/// @notice This contract is the proxy for ETH interactions with the leNFT protocol
contract WETHGateway is ReentrancyGuard, Context, IERC721Receiver {
    IAddressesProvider private _addressProvider;
    IWETH private _weth;

    /// @notice Constructor for the WETHGateway contract
    /// @param addressesProvider The address of the AddressesProvider contract
    constructor(IAddressesProvider addressesProvider, IWETH weth) {
        _addressProvider = addressesProvider;
        _weth = weth;
    }

    /// @notice Deposit ETH in a wETH lending pool
    /// @param lendingPool Lending pool to deposit intoto
    function depositLendingPool(
        address lendingPool
    ) external payable nonReentrant {
        require(
            IERC4626(lendingPool).asset() == address(_weth),
            "Pool underlying is not WETH"
        );

        // Deposit and approve WETH
        _weth.deposit{value: msg.value}();
        _weth.approve(lendingPool, msg.value);

        IERC4626(lendingPool).deposit(msg.value, _msgSender());
    }

    /// @notice Withdraw ETH from a WETH lending pool
    /// @param amount Amount of ETH to be withdrawn100
    function withdrawLendingPool(
        address lendingPool,
        uint256 amount
    ) external nonReentrant {
        require(
            IERC4626(lendingPool).asset() == address(_weth),
            "Pool underlying is not WETH"
        );

        IERC4626(lendingPool).withdraw(amount, address(this), _msgSender());
        _weth.withdraw(amount);

        (bool sent, ) = _msgSender().call{value: amount}("");
        require(sent, "Failed to send Ether");
    }

    /// @notice Borrow ETH from a WETH lending pool while an NFT as collateral
    /// @dev NFT approval needs to be given to the LoanCenter contract
    /// @param amount Amount of ETH to be borrowed
    /// @param nftAddress Address of the NFT collateral
    /// @param nftTokenIds Token ids of the NFT(s) collateral
    /// @param request ID of the collateral price request sent by the trusted server
    /// @param packet Signed collateral price request sent by the trusted server
    function borrow(
        uint256 amount,
        address nftAddress,
        uint256[] calldata nftTokenIds,
        uint256 genesisNFTId,
        bytes32 request,
        Trustus.TrustusPacket calldata packet
    ) external nonReentrant {
        ILendingMarket market = ILendingMarket(
            _addressProvider.getLendingMarket()
        );

        // Transfer the collateral to the WETH Gateway
        for (uint256 i = 0; i < nftTokenIds.length; i++) {
            IERC721(nftAddress).safeTransferFrom(
                _msgSender(),
                address(this),
                nftTokenIds[i]
            );

            // Approve the collateral to be moved by the market
            IERC721(nftAddress).approve(address(market), nftTokenIds[i]);
        }

        market.borrow(
            _msgSender(),
            address(_weth),
            amount,
            nftAddress,
            nftTokenIds,
            genesisNFTId,
            request,
            packet
        );

        // Make sure enough ETH was received
        assert(_weth.balanceOf(address(this)) == amount);

        _weth.withdraw(amount);

        (bool sent, ) = _msgSender().call{value: amount}("");
        require(sent, "Failed to send Ether");
    }

    /// @notice Repay an an active loan with ETH
    /// @param loanId The ID of the loan to be paid
    function repay(uint256 loanId) external payable nonReentrant {
        address pool = ILoanCenter(_addressProvider.getLoanCenter())
            .getLoanLendingPool(loanId);
        ILendingMarket market = ILendingMarket(
            _addressProvider.getLendingMarket()
        );

        require(
            IERC4626(pool).asset() == address(_weth),
            "Loan pool underlying is not WETH"
        );

        // Deposit and approve WETH
        _weth.deposit{value: msg.value}();
        _weth.approve(pool, msg.value);

        // Repay loan
        market.repay(loanId, msg.value);
    }

    /// @notice Deposit ETH and/or NFTs into a trading pool to provide liquidity
    /// @param pool The trading pool address
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
    ) external payable nonReentrant {
        require(
            ITradingPool(pool).getToken() == address(_weth),
            "Pool underlying is not WETH"
        );

        // Transfer the NFTs to the WETH Gateway and approve them for use
        for (uint i = 0; i < nftIds.length; i++) {
            IERC721(ITradingPool(pool).getNFT()).safeTransferFrom(
                _msgSender(),
                address(this),
                nftIds[i]
            );
        }
        IERC721(ITradingPool(pool).getNFT()).setApprovalForAll(pool, true);

        // Deposit and approve WETH
        _weth.deposit{value: msg.value}();
        _weth.approve(pool, msg.value);

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
    ) external nonReentrant {
        require(
            ITradingPool(pool).getToken() == address(_weth),
            "Pool underlying is not WETH"
        );

        // Send LP NFT to this contract
        IERC721(pool).safeTransferFrom(_msgSender(), address(this), lpId);

        // Get LP info so we can send the correct amounts back
        DataTypes.LiquidityPair memory lp = ITradingPool(pool).getLP(lpId);

        // Remove liquidity
        ITradingPool(pool).removeLiquidity(lpId);

        // Send NFTs back to the user
        for (uint i = 0; i < lp.nftIds.length; i++) {
            IERC721(pool).safeTransferFrom(
                address(this),
                _msgSender(),
                lp.nftIds[i]
            );
        }

        // Send ETH back to the user
        _weth.withdraw(lp.tokenAmount);

        (bool sent, ) = _msgSender().call{value: lp.tokenAmount}("");
        require(sent, "Failed to send Ether");
    }

    /// @notice Withdraws liquidity from a trading pool for a batch of liquidity pairs.
    /// @param pool The address of the trading pool.
    /// @param lpIds The array of liquidity pair ids to withdraw.
    function withdrawBatchTradingPool(
        address pool,
        uint256[] calldata lpIds
    ) external nonReentrant {
        uint256 totalAmount = 0;
        uint256[][] memory nftIds = new uint256[][](lpIds.length);

        require(
            ITradingPool(pool).getToken() == address(_weth),
            "Pool underlying is not WETH"
        );

        // Send LP NFTs to this contract
        for (uint i = 0; i < lpIds.length; i++) {
            IERC721(pool).safeTransferFrom(
                _msgSender(),
                address(this),
                lpIds[i]
            );

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
        for (uint a = 0; a < nftIds.length; a++) {
            for (uint b = 0; b < nftIds[a].length; b++) {
                IERC721(pool).safeTransferFrom(
                    address(this),
                    _msgSender(),
                    nftIds[a][b]
                );
            }
        }

        // Send ETH back to the user
        _weth.withdraw(totalAmount);

        (bool sent, ) = _msgSender().call{value: totalAmount}("");
        require(sent, "Failed to send Ether");
    }

    /// @notice Buys NFT from a trading pool by depositing WETH and specifying the NFT ids and maximum price to pay.
    /// @param pool The address of the trading pool.
    /// @param nftIds The array of NFT ids to buy.
    /// @param maximumPrice The maximum amount of ETH to pay for the purchase.
    function buy(
        address pool,
        uint256[] calldata nftIds,
        uint256 maximumPrice
    ) external payable nonReentrant {
        require(
            ITradingPool(pool).getToken() == address(_weth),
            "Pool underlying is not WETH"
        );

        require(
            msg.value == maximumPrice,
            "Sent value is not equal to maximum price"
        );

        // Deposit and approve WETH
        _weth.deposit{value: msg.value}();
        _weth.approve(pool, msg.value);

        uint256 finalPrice = ITradingPool(pool).buy(
            msg.sender,
            nftIds,
            maximumPrice
        );

        // Send ETH back to the user
        if (msg.value > finalPrice) {
            _weth.withdraw(msg.value - finalPrice);

            (bool sent, ) = _msgSender().call{value: msg.value - finalPrice}(
                ""
            );
            require(sent, "Failed to send Ether");
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
    ) external nonReentrant {
        require(
            ITradingPool(pool).getToken() == address(_weth),
            "Pool underlying is not WETH"
        );

        // Send NFTs to this contract and approve them for pool use
        for (uint i = 0; i < nftIds.length; i++) {
            IERC721(ITradingPool(pool).getNFT()).safeTransferFrom(
                _msgSender(),
                address(this),
                nftIds[i]
            );
        }
        IERC721(ITradingPool(pool).getNFT()).setApprovalForAll(pool, true);

        // Sell NFTs
        uint256 finalPrice = ITradingPool(pool).sell(
            address(this),
            nftIds,
            liquidityPairs,
            minimumPrice
        );

        // Send ETH back to the user
        _weth.withdraw(finalPrice);

        (bool sent, ) = _msgSender().call{value: finalPrice}("");
        require(sent, "Failed to send Ether");
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
        ITradingPool buyPool,
        ITradingPool sellPool,
        uint256[] calldata buyNftIds,
        uint256 maximumBuyPrice,
        uint256[] calldata sellNftIds,
        uint256[] calldata sellLps,
        uint256 minimumSellPrice
    ) external payable nonReentrant {
        ISwapRouter swapRouter = ISwapRouter(_addressProvider.getSwapRouter());

        require(
            buyPool.getToken() == address(_weth),
            "Buy pool underlying is not WETH"
        );
        require(
            sellPool.getToken() == address(_weth),
            "Sell pool underlying is not WETH"
        );

        // Make sure the msg.value covers the swap
        if (maximumBuyPrice > minimumSellPrice) {
            require(
                msg.value == maximumBuyPrice - minimumSellPrice,
                "Not enough ETH sent to cover swap change"
            );

            // Deposit and approve WETH
            _weth.deposit{value: msg.value}();
            _weth.approve(address(swapRouter), msg.value);
        }

        // Send NFTs to this contract and approve them for pool use
        for (uint i = 0; i < sellNftIds.length; i++) {
            IERC721(sellPool.getNFT()).safeTransferFrom(
                _msgSender(),
                address(this),
                sellNftIds[i]
            );
        }
        IERC721(sellPool.getNFT()).setApprovalForAll(address(sellPool), true);

        // Swap
        uint256 returnedAmount = swapRouter.swap(
            buyPool,
            sellPool,
            buyNftIds,
            maximumBuyPrice,
            sellNftIds,
            sellLps,
            minimumSellPrice
        );

        // Send NFTs back to the user
        for (uint i = 0; i < buyNftIds.length; i++) {
            IERC721(buyPool.getNFT()).safeTransferFrom(
                address(this),
                _msgSender(),
                buyNftIds[i]
            );
        }

        // Send ETH back to the user
        if (returnedAmount > 0) {
            _weth.withdraw(returnedAmount);

            (bool sent, ) = _msgSender().call{value: returnedAmount}("");
            require(sent, "Failed to send Ether");
        }
    }

    function depositBribe

    // So we can receive the collateral from the user when borrowing
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

    // Add receive ETH function
    // Intended to receive ETH from WETH contract
    receive() external payable {
        require(
            msg.sender == address(_weth),
            "Received ETH from unknown source not allowed"
        );
    }

    /**
     * @dev Revert fallback calls
     */
    fallback() external payable {
        revert("Fallback not allowed");
    }
}
