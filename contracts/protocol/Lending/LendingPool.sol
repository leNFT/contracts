// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.8.17;

import {ILendingPool} from "../../interfaces/ILendingPool.sol";
import {ERC4626} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import {IAddressesProvider} from "../../interfaces/IAddressesProvider.sol";
import {IInterestRate} from "../../interfaces/IInterestRate.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Context} from "@openzeppelin/contracts/utils/Context.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {DataTypes} from "../../libraries/types/DataTypes.sol";
import {ConfigTypes} from "../../libraries/types/ConfigTypes.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ValidationLogic} from "../../libraries/logic/ValidationLogic.sol";

contract LendingPool is Context, ILendingPool, ERC20, ERC4626, Ownable {
    IAddressesProvider private _addressProvider;
    IERC20 internal _asset;
    uint256 internal _debt;
    uint256 internal _borrowRate;
    uint256 internal _cumulativeDebtBorrowRate;
    bool internal _paused;
    ConfigTypes.LendingPoolConfig internal _LendingPoolConfig;

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
        ConfigTypes.LendingPoolConfig memory LendingPoolConfig
    ) ERC20(name, symbol) ERC4626(asset) {
        require(
            msg.sender == addressProvider.getMarket(),
            "Reserve must be created through market"
        );
        _addressProvider = addressProvider;
        _asset = asset;
        _LendingPoolConfig = LendingPoolConfig;
        _updateBorrowRate();
        _transferOwnership(owner);
    }

    function decimals() public view override(ERC20, ERC4626) returns (uint8) {
        return ERC4626.decimals();
    }

    function getUnderlyingBalance() public view override returns (uint256) {
        return _asset.balanceOf(address(this));
    }

    /** @dev See {IERC4626-totalAssets}. */
    function totalAssets() public view override returns (uint256) {
        return _debt + getUnderlyingBalance();
    }

    function _deposit(
        address caller,
        address receiver,
        uint256 assets,
        uint256 shares
    ) internal override {
        require(!_paused, "Reserve is paused");

        ValidationLogic.validateDeposit(address(this), assets);

        ERC4626._deposit(caller, receiver, assets, shares);

        _updateBorrowRate();
    }

    function _withdraw(
        address caller,
        address receiver,
        address owner,
        uint256 assets,
        uint256 shares
    ) internal override {
        require(!_paused, "Reserve is paused");

        ValidationLogic.validateDeposit(address(this), assets);

        ERC4626._withdraw(caller, receiver, owner, assets, shares);

        _updateBorrowRate();
    }

    function transferUnderlying(
        address to,
        uint256 amount,
        uint256 borrowRate
    ) external override onlyMarket {
        require(!_paused, "Reserve is paused");

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
        require(!_paused, "Reserve is paused");

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
        require(!_paused, "Reserve is paused");

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
        return _LendingPoolConfig.maximumUtilizationRate;
    }

    function getBorrowRate() external view override returns (uint256) {
        return _borrowRate;
    }

    function _updateBorrowRate() internal {
        _borrowRate = IInterestRate(
            IAddressesProvider(_addressProvider).getInterestRate()
        ).calculateBorrowRate(getUnderlyingBalance(), _debt);
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
        if (totalAssets() > 0) {
            supplyRate = (_cumulativeDebtBorrowRate * _debt) / totalAssets();
        }
        return supplyRate;
    }

    function getDebt() external view override returns (uint256) {
        return _debt;
    }

    function getUtilizationRate() external view override returns (uint256) {
        return
            IInterestRate(_addressProvider.getInterestRate())
                .calculateUtilizationRate(getUnderlyingBalance(), _debt);
    }

    function getLiquidationPenalty() external view override returns (uint256) {
        return _LendingPoolConfig.liquidationPenalty;
    }

    function setLiquidationPenalty(
        uint256 liquidationPenalty
    ) external onlyOwner {
        _LendingPoolConfig.liquidationPenalty = liquidationPenalty;
    }

    function getLiquidationFee() external view override returns (uint256) {
        return _LendingPoolConfig.protocolLiquidationFee;
    }

    function setLiquidationFee(
        uint256 protocolLiquidationFee
    ) external onlyOwner {
        _LendingPoolConfig.protocolLiquidationFee = protocolLiquidationFee;
    }

    function getTVLSafeguard() external view override returns (uint256) {
        return _LendingPoolConfig.tvlSafeguard;
    }

    function setTVLSafeguard(uint256 tvlSafeguard) external onlyOwner {
        _LendingPoolConfig.tvlSafeguard = tvlSafeguard;
    }

    function setPause(bool paused) external onlyOwner {
        _paused = paused;
    }
}
