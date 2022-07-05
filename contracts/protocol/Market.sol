// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.8.15;

import {IMarket} from "../interfaces/IMarket.sol";
import {NftLogic} from "../libraries/logic/NftLogic.sol";
import {SupplyLogic} from "../libraries/logic/SupplyLogic.sol";
import {LiquidationLogic} from "../libraries/logic/LiquidationLogic.sol";
import {BorrowLogic} from "../libraries/logic/BorrowLogic.sol";
import {DataTypes} from "../libraries/types/DataTypes.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {IMarketAddressesProvider} from "../interfaces/IMarketAddressesProvider.sol";

contract Market is Initializable, IMarket, OwnableUpgradeable {
    mapping(address => address) private _reserves;
    IMarketAddressesProvider private _addressesProvider;
    uint256 internal constant _NOT_ENTERED = 0;
    uint256 internal constant _ENTERED = 1;
    uint256 internal _status;

    /**
     * @dev Prevents a contract from calling itself, directly or indirectly.
     * Calling a `nonReentrant` function from another `nonReentrant`
     * function is not supported. It is possible to prevent this from happening
     * by making the `nonReentrant` function external, and making it call a
     * `private` function that does the actual work.
     */
    modifier nonReentrant() {
        // On the first call to nonReentrant, _notEntered will be true
        require(_status != _ENTERED, "ReentrancyGuard: reentrant call");

        // Any calls to nonReentrant after this point will fail
        _status = _ENTERED;

        _;

        // By storing the original value once again, a refund is triggered (see
        // https://eips.ethereum.org/EIPS/eip-2200)
        _status = _NOT_ENTERED;
    }

    // Initialize the market
    function initialize(IMarketAddressesProvider addressesProvider)
        external
        initializer
    {
        __Ownable_init();
        _addressesProvider = addressesProvider;
    }

    // Deposit an asset in the reserve
    function deposit(address asset, uint256 amount)
        external
        override
        nonReentrant
    {
        SupplyLogic.deposit(_reserves, asset, amount);
    }

    // Withdraw an asset from the reserve
    function withdraw(address asset, uint256 amount)
        external
        override
        nonReentrant
    {
        SupplyLogic.withdraw(_reserves, asset, amount);
    }

    // Borrow an asset from the reserve while using an NFT collateral
    function borrow(
        address asset,
        uint256 amount,
        address nftAddress,
        uint256 nftTokenID
    ) external override nonReentrant {
        BorrowLogic.borrow(
            _addressesProvider,
            _reserves,
            msg.sender,
            asset,
            amount,
            nftAddress,
            nftTokenID
        );
    }

    // Repay an asset borrowed from the reserve while using an NFT collateral
    function repay(uint256 loanId) external override nonReentrant {
        BorrowLogic.repay(_addressesProvider, _reserves, loanId, msg.sender);
    }

    // Liquidate an asset borrowed from the reserve
    function liquidate(uint256 loanId) external override nonReentrant {
        LiquidationLogic.liquidate(
            _addressesProvider,
            _reserves,
            loanId,
            msg.sender
        );
    }

    // Init a supply side reserve
    function addReserve(address asset, address reserveAddress)
        external
        onlyOwner
    {
        _reserves[asset] = reserveAddress;
    }

    // Get a reserve address
    function getReserveAddress(address asset) external view returns (address) {
        return _reserves[asset];
    }
}
