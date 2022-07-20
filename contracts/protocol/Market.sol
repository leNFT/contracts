// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.8.15;

import {IMarket} from "../interfaces/IMarket.sol";
import {SupplyLogic} from "../libraries/logic/SupplyLogic.sol";
import {LiquidationLogic} from "../libraries/logic/LiquidationLogic.sol";
import {BorrowLogic} from "../libraries/logic/BorrowLogic.sol";
import {DataTypes} from "../libraries/types/DataTypes.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {IMarketAddressesProvider} from "../interfaces/IMarketAddressesProvider.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract Market is Initializable, IMarket, OwnableUpgradeable, ReentrancyGuard {
    mapping(address => address) private _reserves;
    IMarketAddressesProvider private _addressProvider;
    uint256 internal constant _NOT_ENTERED = 0;
    uint256 internal constant _ENTERED = 1;
    uint256 internal _status;

    // Initialize the market
    function initialize(IMarketAddressesProvider addressesProvider)
        external
        initializer
    {
        __Ownable_init();
        _addressProvider = addressesProvider;
    }

    // Deposit an asset in the reserve
    function deposit(address asset, uint256 amount)
        external
        override
        nonReentrant
    {
        SupplyLogic.deposit(_reserves, asset, amount);

        emit Deposit(msg.sender, asset, amount);
    }

    // Withdraw an asset from the reserve
    function withdraw(address asset, uint256 amount)
        external
        override
        nonReentrant
    {
        SupplyLogic.withdraw(_addressProvider, _reserves, asset, amount);

        emit Withdraw(msg.sender, asset, amount);
    }

    // Borrow an asset from the reserve while using an NFT collateral
    function borrow(
        address asset,
        uint256 amount,
        address nftAddress,
        uint256 nftTokenID
    ) external override nonReentrant {
        BorrowLogic.borrow(
            _addressProvider,
            _reserves,
            asset,
            amount,
            nftAddress,
            nftTokenID
        );

        emit Borrow(msg.sender, asset, nftAddress, nftTokenID, amount);
    }

    // Repay an asset borrowed from the reserve while using an NFT collateral
    function repay(uint256 loanId) external override nonReentrant {
        BorrowLogic.repay(_addressProvider, loanId);

        emit Repay(msg.sender, loanId);
    }

    // Liquidate an asset borrowed from the reserve
    function liquidate(uint256 loanId) external override nonReentrant {
        LiquidationLogic.liquidate(_addressProvider, loanId);

        emit Liquidate(msg.sender, loanId);
    }

    // Init a supply side reserve
    function addReserve(address asset, address reserveAddress)
        external
        onlyOwner
    {
        //Approve reserve use of Market balance
        IERC20(asset).approve(reserveAddress, 2**256 - 1);

        _reserves[asset] = reserveAddress;
    }

    // Get a reserve address
    function getReserveAddress(address asset) external view returns (address) {
        return _reserves[asset];
    }

    // Check if asset is supported
    function isAssetSupported(address asset) external view returns (bool) {
        return _reserves[asset] != address(0);
    }
}
