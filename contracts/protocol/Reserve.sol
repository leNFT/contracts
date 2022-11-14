// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.8.17;

import {IReserve} from "../interfaces/IReserve.sol";
import {ERC4626} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import {IAddressesProvider} from "../interfaces/IAddressesProvider.sol";
import {IInterestRate} from "../interfaces/IInterestRate.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Context} from "@openzeppelin/contracts/utils/Context.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {DataTypes} from "../libraries/types/DataTypes.sol";
import {ConfigTypes} from "../libraries/types/ConfigTypes.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ValidationLogic} from "../libraries/logic/ValidationLogic.sol";

contract Reserve is Context, IReserve, ERC20, ERC4626, Ownable {
    IAddressesProvider private _addressProvider;
    IERC20 internal _asset;
    uint256 internal _debt;
    uint256 internal _borrowRate;
    uint256 internal _cumulativeDebtBorrowRate;
    ConfigTypes.ReserveConfig internal _reserveConfig;

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
        IERC20 asset,
        string memory name,
        string memory symbol,
        ConfigTypes.ReserveConfig memory reserveConfig
    ) ERC20(name, symbol) ERC4626(asset) {
        require(
            msg.sender == addressProvider.getMarket(),
            "Reserve must be created through market"
        );
        _addressProvider = addressProvider;
        _asset = asset;
        _reserveConfig = reserveConfig;
        _updateBorrowRate();
        _transferOwnership(owner);
    }

    function decimals() public view override(ERC20, ERC4626) returns (uint8) {
        return super.decimals();
    }

    /** @dev See {IERC4626-totalAssets}. */
    function totalAssets() public view override returns (uint256) {
        return _debt + _asset.balanceOf(address(this));
    }

    function _deposit(
        address caller,
        address receiver,
        uint256 assets,
        uint256 shares
    ) internal override {
        ValidationLogic.validateDeposit(address(this), assets);

        super._deposit(caller, receiver, assets, shares);

        _updateBorrowRate();
    }

    function _withdraw(
        address caller,
        address receiver,
        address owner,
        uint256 assets,
        uint256 shares
    ) internal override {
        ValidationLogic.validateDeposit(address(this), assets);

        super._withdraw(caller, receiver, owner, assets, shares);

        _updateBorrowRate();
    }

    function transferUnderlying(
        address to,
        uint256 amount,
        uint256 borrowRate
    ) external override onlyMarket {
        // Send the underlying to user
        _asset.safeTransfer(to, amount);

        // Update the cummulative borrow rate
        _updateCumulativeDebtBorrowRate(true, amount, borrowRate);

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
        _asset.safeTransferFrom(from, address(this), amount + interest);
        _updateCumulativeDebtBorrowRate(false, amount, borrowRate);
        _debt -= amount;
        _updateBorrowRate();
    }

    function receiveUnderlyingDefaulted(
        address from,
        uint256 amount,
        uint256 borrowRate,
        uint256 defaultedDebt
    ) external override onlyMarket {
        _asset.safeTransferFrom(from, address(this), amount);
        _updateCumulativeDebtBorrowRate(false, defaultedDebt, borrowRate);
        _debt -= defaultedDebt;
        _updateBorrowRate();
    }

    function getMaximumUtilizationRate()
        external
        view
        override
        returns (uint256)
    {
        return _reserveConfig.maximumUtilizationRate;
    }

    function getBorrowRate() external view override returns (uint256) {
        return _borrowRate;
    }

    function _updateBorrowRate() internal {
        _borrowRate = IInterestRate(
            IAddressesProvider(_addressProvider).getInterestRate()
        ).calculateBorrowRate(_asset.balanceOf(address(this)), _debt);
    }

    // Updates the mean of the borrow rate in our debt
    function _updateCumulativeDebtBorrowRate(
        bool increaseDebt,
        uint256 amount,
        uint256 borrowRate
    ) internal {
        if (increaseDebt) {
            _cumulativeDebtBorrowRate =
                ((_debt * _cumulativeDebtBorrowRate) + (amount * borrowRate)) /
                (_debt + amount);
        } else {
            if ((_debt - amount) == 0) {
                _cumulativeDebtBorrowRate = 0;
            } else {
                _cumulativeDebtBorrowRate =
                    ((_debt * _cumulativeDebtBorrowRate) -
                        (amount * borrowRate)) /
                    (_debt - amount);
            }
        }
    }

    function getSupplyRate() external view override returns (uint256) {
        uint256 supplyRate = 0;
        if ((_debt + _asset.balanceOf(address(this))) > 0) {
            supplyRate =
                (_cumulativeDebtBorrowRate * _debt) /
                (_debt + _asset.balanceOf(address(this)));
        }
        return supplyRate;
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
                .calculateUtilizationRate(
                    _asset.balanceOf(address(this)),
                    _getDebt()
                );
    }

    function getLiquidationPenalty() external view override returns (uint256) {
        return _reserveConfig.liquidationPenalty;
    }

    function setLiquidationPenalty(uint256 liquidationPenalty)
        external
        onlyOwner
    {
        _reserveConfig.liquidationPenalty = liquidationPenalty;
    }

    function getLiquidationFee() external view override returns (uint256) {
        return _reserveConfig.protocolLiquidationFee;
    }

    function setLiquidationFee(uint256 protocolLiquidationFee)
        external
        onlyOwner
    {
        _reserveConfig.protocolLiquidationFee = protocolLiquidationFee;
    }

    function getTVLSafeguard() external view override returns (uint256) {
        return _reserveConfig.tvlSafeguard;
    }

    function setTVLSafeguard(uint256 tvlSafeguard) external onlyOwner {
        _reserveConfig.tvlSafeguard = tvlSafeguard;
    }
}
