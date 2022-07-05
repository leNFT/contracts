// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.8.15;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {IReserve} from "../interfaces/IReserve.sol";
import {SupplyLogic} from "../libraries/logic/SupplyLogic.sol";
import {IMarketAddressesProvider} from "../interfaces/IMarketAddressesProvider.sol";
import {IInterestRate} from "../interfaces/IInterestRate.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {IERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import {ERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {SafeERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";

contract Reserve is
    Initializable,
    IReserve,
    ERC20Upgradeable,
    OwnableUpgradeable
{
    IMarketAddressesProvider internal _addressProvider;
    address internal _asset;
    uint256 internal _debt;
    uint256 internal _borrowRate;
    uint256 internal _cumulativeBorrowRate;
    uint256 internal _liquidationPenalty;
    uint256 internal _protocolLiquidationFee;

    using SafeERC20Upgradeable for IERC20Upgradeable;

    modifier onlyMarket() {
        require(
            _msgSender() == address(_addressProvider.getMarketAddress()),
            "Caller must be Market contract"
        );
        _;
    }

    function initialize(
        IMarketAddressesProvider addressProvider,
        address asset,
        string calldata name,
        string calldata symbol,
        uint256 liquidationPenalty,
        uint256 protocolLiquidationFee
    ) external initializer {
        __Ownable_init();
        __ERC20_init(name, symbol);
        _addressProvider = addressProvider;
        _asset = asset;
        _liquidationPenalty = liquidationPenalty;
        _protocolLiquidationFee = protocolLiquidationFee;
    }

    function mint(address user, uint256 amount) external override onlyMarket {
        _mint(user, amount);
    }

    function burn(address user, uint256 amount) external override onlyMarket {
        _burn(user, amount);
    }

    function depositUnderlying(address depositor, uint256 amount)
        external
        override
        onlyMarket
    {
        IERC20Upgradeable(_asset).safeTransferFrom(
            depositor,
            address(this),
            amount
        );

        _updateBorrowRate();
    }

    function getMaximumWithdrawalAmount(address to)
        external
        view
        override
        returns (uint256)
    {
        return SupplyLogic.maximumWithdrawalAmount(address(this), to);
    }

    function withdrawUnderlying(address to, uint256 amount)
        external
        override
        onlyMarket
    {
        IERC20Upgradeable(_asset).safeTransfer(to, amount);

        _updateBorrowRate();
    }

    function transferUnderlying(
        address to,
        uint256 amount,
        uint256 borrowRate
    ) external override onlyMarket {
        // Send the underlying to user
        IERC20Upgradeable(_asset).safeTransfer(to, amount);

        // Update the cummulative borrow rate
        _updateCumulativeBorrowRate(true, amount, borrowRate);

        // Update the debt
        _debt += amount;

        // Update the borrow rate
        _updateBorrowRate();
    }

    function receiveUnderlying(
        address from,
        uint256 amount,
        uint256 borrowRate,
        uint256 interest
    ) external override onlyMarket {
        IERC20Upgradeable(_asset).safeTransferFrom(
            from,
            address(this),
            amount + interest
        );
        _updateCumulativeBorrowRate(false, amount, borrowRate);
        _debt -= amount;
        _updateBorrowRate();
    }

    function receiveUnderlyingDefaulted(
        address from,
        uint256 amount,
        uint256 borrowRate,
        uint256 defaultedDebt
    ) external override onlyMarket {
        IERC20Upgradeable(_asset).safeTransferFrom(from, address(this), amount);
        _updateCumulativeBorrowRate(false, defaultedDebt, borrowRate);
        _debt -= defaultedDebt;
        _updateBorrowRate();
    }

    function getUnderlyingBalance() external view override returns (uint256) {
        return _getUnderlyingBalance();
    }

    function _getUnderlyingBalance() internal view returns (uint256) {
        return IERC20Upgradeable(_asset).balanceOf(address(this));
    }

    function getBorrowRate() external view override returns (uint256) {
        return _borrowRate;
    }

    function _updateBorrowRate() internal {
        _borrowRate = IInterestRate(
            IMarketAddressesProvider(_addressProvider).getInterestRate()
        ).calculateBorrowRate(_getUnderlyingBalance(), _debt);
    }

    // Updates the cumulative borrow rate
    // newDebt: The new debt after
    function _updateCumulativeBorrowRate(
        bool increaseDebt,
        uint256 amount,
        uint256 borrowRate
    ) internal {
        if (increaseDebt) {
            _cumulativeBorrowRate =
                ((_debt * _cumulativeBorrowRate) + (amount * borrowRate)) /
                (_debt + amount);
        } else {
            if ((_debt - amount) == 0) {
                _cumulativeBorrowRate = 0;
            } else {
                _cumulativeBorrowRate =
                    ((_debt * _cumulativeBorrowRate) - (amount * borrowRate)) /
                    (_debt - amount);
            }
        }
    }

    function getCumulativeBorrowRate()
        external
        view
        override
        returns (uint256)
    {
        return _cumulativeBorrowRate;
    }

    function getDebt() external view override returns (uint256) {
        return _getDebt();
    }

    function _getDebt() internal view returns (uint256) {
        return _debt;
    }

    function getUtilizationRate() external view override returns (uint256) {
        return
            IInterestRate(_addressProvider.getInterestRate())
                .calculateUtilizationRate(_getUnderlyingBalance(), _getDebt());
    }

    function getLiquidationPenalty() external view override returns (uint256) {
        return _liquidationPenalty;
    }

    function changeLiquidationPenalty(uint256 liquidationPenalty)
        external
        onlyOwner
    {
        _liquidationPenalty = liquidationPenalty;
    }

    function getProtocolLiquidationFee()
        external
        view
        override
        returns (uint256)
    {
        return _protocolLiquidationFee;
    }

    function changeProtocolLiquidationFee(uint256 protocolLiquidationFee)
        external
        onlyOwner
    {
        _protocolLiquidationFee = protocolLiquidationFee;
    }
}
