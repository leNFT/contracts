// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.8.17;

import {IWETH} from "../interfaces/IWETH.sol";
import {ILendingMarket} from "../interfaces/ILendingMarket.sol";
import {ILendingMarket} from "../interfaces/ILendingMarket.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {IERC721Receiver} from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import {DataTypes} from "../libraries/types/DataTypes.sol";
import {ILoanCenter} from "../interfaces/ILoanCenter.sol";
import {ISwapRouter} from "../interfaces/ISwapRouter.sol";

import {ITradingPool} from "../interfaces/ITradingPool.sol";
import {IERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {Trustus} from "./Trustus/Trustus.sol";
import {Context} from "@openzeppelin/contracts/utils/Context.sol";
import {IAddressesProvider} from "../interfaces/IAddressesProvider.sol";
import "hardhat/console.sol";

contract WETHGateway is ReentrancyGuard, Context, IERC721Receiver {
    IAddressesProvider private _addressProvider;

    constructor(IAddressesProvider addressesProvider) {
        _addressProvider = addressesProvider;
    }

    /// @notice Deposit ETH in a wETH lending pool
    /// @dev Needs to give approval to the corresponding vault
    function depositLendingPool(
        address lendingPool
    ) external payable nonReentrant {
        IWETH weth = IWETH(_addressProvider.getWETH());

        require(
            IERC4626(lendingPool).asset() == address(weth),
            "Pool underlying is not WETH"
        );

        // Deposit and approve WETH
        weth.deposit{value: msg.value}();
        weth.approve(lendingPool, msg.value);

        IERC4626(lendingPool).deposit(msg.value, _msgSender());
    }

    /// @notice Withdraw an asset from a lending pool
    /// @param amount Amount of the asset to be withdrawn
    function withdrawLendingPool(
        address lendingPool,
        uint256 amount
    ) external nonReentrant {
        IWETH weth = IWETH(_addressProvider.getWETH());
        require(
            IERC4626(lendingPool).asset() == address(weth),
            "Pool underlying is not WETH"
        );

        IERC4626(lendingPool).withdraw(amount, address(this), _msgSender());
        weth.withdraw(amount);

        (bool sent, ) = _msgSender().call{value: amount}("");
        require(sent, "Failed to send Ether");
    }

    /// @notice Borrow an asset from the pool while an NFT as collateral
    /// @dev NFT approval needs to be given to the LoanCenter contract
    /// @param amount Amount of the asset to be borrowed
    /// @param nftAddress Address of the NFT collateral
    /// @param nftTokenId Token id of the NFT collateral
    /// @param request ID of the collateral price request sent by the trusted server
    /// @param packet Signed collateral price request sent by the trusted server
    function borrow(
        uint256 amount,
        address nftAddress,
        uint256 nftTokenId,
        uint256 genesisNFTId,
        bytes32 request,
        Trustus.TrustusPacket calldata packet
    ) external nonReentrant {
        ILendingMarket market = ILendingMarket(
            _addressProvider.getLendingMarket()
        );
        IWETH weth = IWETH(_addressProvider.getWETH());

        // Transfer the collateral to the WETH Gateway
        IERC721(nftAddress).safeTransferFrom(
            _msgSender(),
            address(this),
            nftTokenId
        );

        // Approve the collateral to be moved by the market
        IERC721(nftAddress).approve(address(market), nftTokenId);

        market.borrow(
            _msgSender(),
            address(weth),
            amount,
            nftAddress,
            nftTokenId,
            genesisNFTId,
            request,
            packet
        );

        require(
            weth.balanceOf(address(this)) == amount,
            "Not enough WETH received."
        );

        weth.withdraw(amount);

        (bool sent, ) = _msgSender().call{value: amount}("");
        require(sent, "Failed to send Ether");
    }

    /// @notice Repay an an active loanreceive and
    /// @param loanId The ID of the loan to be paid
    function repay(uint256 loanId) external payable nonReentrant {
        address pool = ILoanCenter(_addressProvider.getLoanCenter())
            .getLoanLendingPool(loanId);
        ILendingMarket market = ILendingMarket(
            _addressProvider.getLendingMarket()
        );
        IWETH weth = IWETH(_addressProvider.getWETH());

        require(
            IERC4626(pool).asset() == address(weth),
            "Loan pool underlying is not WETH"
        );

        // Deposit and approve WETH
        weth.deposit{value: msg.value}();
        weth.approve(pool, msg.value);

        // Repay loan
        market.repay(loanId, msg.value);
    }

    function depositTradingPool(
        address pool,
        uint256[] memory nftIds,
        address curve,
        uint256 delta,
        uint256 initialPrice
    ) external payable nonReentrant {
        IWETH weth = IWETH(_addressProvider.getWETH());

        require(
            ITradingPool(pool).getToken() == address(weth),
            "Pool underlying is not WETH"
        );

        // Transfer the NFTs to the WETH Gateway
        for (uint i = 0; i < nftIds.length; i++) {
            IERC721(ITradingPool(pool).getNFT()).safeTransferFrom(
                _msgSender(),
                address(this),
                nftIds[i]
            );
        }

        // Deposit and approve WETH
        weth.deposit{value: msg.value}();
        weth.approve(pool, msg.value);

        ITradingPool(pool).addLiquidity(
            msg.sender,
            nftIds,
            msg.value,
            curve,
            delta,
            initialPrice
        );
    }

    function withdrawTradingPool(
        address pool,
        uint256 lpId
    ) external nonReentrant {
        IWETH weth = IWETH(_addressProvider.getWETH());

        require(
            ITradingPool(pool).getToken() == address(weth),
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
        weth.withdraw(lp.tokenAmount);

        (bool sent, ) = _msgSender().call{value: lp.tokenAmount}("");
        require(sent, "Failed to send Ether");
    }

    function buy(
        address pool,
        uint256[] memory nftIds,
        uint256 maximumPrice
    ) external payable nonReentrant {
        IWETH weth = IWETH(_addressProvider.getWETH());

        require(
            ITradingPool(pool).getToken() == address(weth),
            "Pool underlying is not WETH"
        );

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

            (bool sent, ) = _msgSender().call{value: msg.value - finalPrice}(
                ""
            );
            require(sent, "Failed to send Ether");
        }
    }

    function sell(
        address pool,
        uint256[] memory nftIds,
        uint256[] memory liquidityPairs,
        uint256 minimumPrice
    ) external nonReentrant {
        IWETH weth = IWETH(_addressProvider.getWETH());

        require(
            ITradingPool(pool).getToken() == address(weth),
            "Pool underlying is not WETH"
        );

        // Send NFTs to this contract
        for (uint i = 0; i < nftIds.length; i++) {
            IERC721(ITradingPool(pool).getNFT()).safeTransferFrom(
                address(this),
                _msgSender(),
                nftIds[i]
            );
        }

        // Sell NFTs
        uint256 finalPrice = ITradingPool(pool).sell(
            address(this),
            nftIds,
            liquidityPairs,
            minimumPrice
        );

        // Send ETH back to the user
        weth.withdraw(finalPrice);

        (bool sent, ) = _msgSender().call{value: finalPrice}("");
        require(sent, "Failed to send Ether");
    }

    function swap(
        ITradingPool buyPool,
        ITradingPool sellPool,
        uint256[] memory buyNftIds,
        uint256 maximumBuyPrice,
        uint256[] memory sellNftIds,
        uint256[] memory sellLps,
        uint256 minimumSellPrice
    ) external payable nonReentrant {
        IWETH weth = IWETH(_addressProvider.getWETH());

        require(
            buyPool.getToken() == address(weth),
            "Buy pool underlying is not WETH"
        );
        require(
            sellPool.getToken() == address(weth),
            "Sell pool underlying is not WETH"
        );

        // Send NFTs to this contract
        for (uint i = 0; i < sellNftIds.length; i++) {
            IERC721(sellPool.getNFT()).safeTransferFrom(
                address(this),
                _msgSender(),
                sellNftIds[i]
            );
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

        // Send ETH back to the user
        weth.withdraw(returnedAmount);

        (bool sent, ) = _msgSender().call{value: returnedAmount}("");
        require(sent, "Failed to send Ether");
    }

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
            _msgSender() == _addressProvider.getWETH(),
            "Receive not allowed"
        );
    }

    /**
     * @dev Revert fallback calls
     */
    fallback() external payable {
        revert("Fallback not allowed");
    }
}
