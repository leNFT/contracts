// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.8.17;

import {IWETH} from "../interfaces/IWETH.sol";
import {IMarket} from "../interfaces/IMarket.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {IERC721Receiver} from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import {ILoanCenter} from "../interfaces/ILoanCenter.sol";
import {IERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {Trustus} from "./Trustus/Trustus.sol";
import {Context} from "@openzeppelin/contracts/utils/Context.sol";
import {IAddressesProvider} from "../interfaces/IAddressesProvider.sol";

contract WETHGateway is ReentrancyGuard, Context, IERC721Receiver {
    IAddressesProvider private _addressProvider;

    constructor(IAddressesProvider addressesProvider) {
        _addressProvider = addressesProvider;
    }

    /// @notice Deposit ETH in the wETH lending vault
    /// @dev Needs to give approval to the corresponding vault
    function depositETH(address lendingVault) external payable nonReentrant {
        IWETH weth = IWETH(_addressProvider.getWETH());

        require(
            IERC4626(lendingVault).asset() == address(weth),
            "Reserve underlying is not WETH"
        );

        // Deposit and approve WETH
        weth.deposit{value: msg.value}();
        weth.approve(lendingVault, msg.value);

        IERC4626(lendingVault).deposit(msg.value, _msgSender());
    }

    /// @notice Withdraw an asset from the reserve
    /// @param amount Amount of the asset to be withdrawn
    function withdrawETH(
        address reserve,
        uint256 amount
    ) external nonReentrant {
        IWETH weth = IWETH(_addressProvider.getWETH());
        require(
            IERC4626(reserve).asset() == address(weth),
            "Reserve underlying is not WETH"
        );

        IERC4626(reserve).withdraw(amount, address(this), _msgSender());
        weth.withdraw(amount);

        (bool sent, ) = _msgSender().call{value: amount}("");
        require(sent, "Failed to send Ether");
    }

    /// @notice Borrow an asset from the reserve while an NFT as collateral
    /// @dev NFT approval needs to be given to the LoanCenter contract
    /// @param amount Amount of the asset to be borrowed
    /// @param nftAddress Address of the NFT collateral
    /// @param nftTokenId Token id of the NFT collateral
    /// @param request ID of the collateral price request sent by the trusted server
    /// @param packet Signed collateral price request sent by the trusted server
    function borrowETH(
        uint256 amount,
        address nftAddress,
        uint256 nftTokenId,
        uint256 genesisNFTId,
        bytes32 request,
        Trustus.TrustusPacket calldata packet
    ) external nonReentrant {
        IMarket market = IMarket(_addressProvider.getLendingMarket());
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

        weth.withdraw(amount);

        (bool sent, ) = _msgSender().call{value: amount}("");
        require(sent, "Failed to send Ether");
    }

    /// @notice Repay an an active loanreceive and
    /// @param loanId The ID of the loan to be paid
    function repayETH(uint256 loanId) external payable nonReentrant {
        address reserve = ILoanCenter(_addressProvider.getLoanCenter())
            .getLoanLendingPool(loanId);
        IMarket market = IMarket(_addressProvider.getLendingMarket());
        IWETH weth = IWETH(_addressProvider.getWETH());

        require(
            IERC4626(reserve).asset() == address(weth),
            "Loan reserve underlying is not WETH"
        );

        // Deposit and approve WETH
        weth.deposit{value: msg.value}();
        weth.approve(reserve, msg.value);

        // Repay loan
        market.repay(loanId, msg.value);
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
            msg.sender == _addressProvider.getWETH(),
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
