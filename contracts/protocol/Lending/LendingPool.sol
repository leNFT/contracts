// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.8.19;

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

/// @title LendingPool contract
/// @dev The LendingPool contract uses the ERC4626 contract to track the shares in a liquidity pool held by users
contract LendingPool is Context, ILendingPool, ERC20, ERC4626, Ownable {
    IAddressesProvider private _addressProvider;
    IERC20 internal _asset;
    uint256 internal _debt;
    uint256 internal _borrowRate;
    uint256 internal _cumulativeDebtBorrowRate;
    bool internal _paused;
    ConfigTypes.LendingPoolConfig internal _lendingPoolConfig;

    using SafeERC20 for IERC20;

    modifier onlyMarket() {
        require(
            _msgSender() == _addressProvider.getLendingMarket(),
            "Callers must be Market contract"
        );
        _;
    }

    /// @notice Constructor to initialize the lending pool contract
    /// @param addressProvider the address provider contract
    /// @param owner the owner of the contract
    /// @param asset the underlying asset of the lending pool
    /// @param name the name of the ERC20 token
    /// @param symbol the symbol of the ERC20 token
    /// @param lendingPoolConfig the configuration parameters for the lending pool
    constructor(
        IAddressesProvider addressProvider,
        address owner,
        IERC20 asset,
        string memory name,
        string memory symbol,
        ConfigTypes.LendingPoolConfig memory lendingPoolConfig
    ) ERC20(name, symbol) ERC4626(asset) {
        require(
            msg.sender == addressProvider.getLendingMarket(),
            "Lending Pool must be created through market"
        );
        _addressProvider = addressProvider;
        _asset = asset;
        _lendingPoolConfig = lendingPoolConfig;
        _updateBorrowRate();
        _transferOwnership(owner);
    }

    /// @notice Get the number of decimals for the underlying asset
    /// @return the number of decimals
    function decimals() public view override(ERC20, ERC4626) returns (uint8) {
        return ERC4626.decimals();
    }

    /// @notice Get the balance of the underlying asset held in the contract
    /// @return the balance of the underlying asset
    function getUnderlyingBalance() public view override returns (uint256) {
        return _asset.balanceOf(address(this));
    }

    /// @notice Get the total assets of the lending pool
    /** @dev See {IERC4626-totalAssets}. */
    /// @return the total assets of the contract (debt + underlying balance)
    function totalAssets() public view override returns (uint256) {
        return _debt + getUnderlyingBalance();
    }

    /// @notice Deposit underlying asset to the contract and mint ERC20 tokens
    /// @param caller the caller of the function
    /// @param receiver the recipient of the ERC20 tokens
    /// @param assets the amount of underlying asset to deposit
    /// @param shares the amount of ERC20 tokens to mint
    function _deposit(
        address caller,
        address receiver,
        uint256 assets,
        uint256 shares
    ) internal override {
        require(!_paused, "Pool is paused");

        ValidationLogic.validateDeposit(
            _addressProvider,
            address(this),
            assets
        );

        ERC4626._deposit(caller, receiver, assets, shares);

        _updateBorrowRate();
    }

    /// @notice Withdraw underlying asset from the contract and burn ERC20 tokens
    /// @param caller the caller of the function
    /// @param receiver the recipient of the underlying asset
    /// @param owner the owner of the ERC20 tokens
    /// @param assets the amount of underlying asset to withdraw
    /// @param shares the amount of ERC20 tokens to burn
    function _withdraw(
        address caller,
        address receiver,
        address owner,
        uint256 assets,
        uint256 shares
    ) internal override {
        require(!_paused, "Pool is paused");

        ValidationLogic.validateWithdrawal(
            _addressProvider,
            address(this),
            assets
        );

        ERC4626._withdraw(caller, receiver, owner, assets, shares);

        _updateBorrowRate();
    }

    /// @notice Transfer the underlying asset to a recipient
    /// @param to the recipient of the underlying asset
    /// @param amount the amount of underlying asset to transfer
    /// @param borrowRate the borrow rate at the time of transfer
    function transferUnderlying(
        address to,
        uint256 amount,
        uint256 borrowRate
    ) external override onlyMarket {
        require(!_paused, "Pool is paused");

        // Send the underlying to user
        _asset.safeTransfer(to, amount);

        // Update the cummulative borrow rate
        _updateCumulativeDebtBorrowRate(true, amount, borrowRate);

        // Update the debt
        _debt += amount;

        // Update the borrow rate
        _updateBorrowRate();
    }

    /// @notice Transfers `amount` of underlying asset and `interest` from `from` to the pool, updates the cumulative debt borrow rate, and updates the borrow rate.
    /// @param from The address from which the underlying asset and interest will be transferred.
    /// @param amount The amount of underlying asset to transfer.
    /// @param borrowRate The current borrow rate.
    /// @param interest The amount of interest to transfer.
    function receiveUnderlying(
        address from,
        uint256 amount,
        uint256 borrowRate,
        uint256 interest
    ) external override onlyMarket {
        require(!_paused, "Pool is paused");

        _asset.safeTransferFrom(from, address(this), amount + interest);
        _updateCumulativeDebtBorrowRate(false, amount, borrowRate);
        _debt -= amount;
        _updateBorrowRate();
    }

    /// @notice Transfers `amount` of underlying asset from `from` to the pool, updates the cumulative debt borrow rate, and updates the borrow rate. The debt is decreased by `defaultedDebt`.
    /// @param from The address from which the underlying asset will be transferred.
    /// @param amount The amount of underlying asset to transfer.
    /// @param borrowRate The current borrow rate.
    /// @param defaultedDebt The defaulted debt to subtract from the debt.

    function receiveUnderlyingDefaulted(
        address from,
        uint256 amount,
        uint256 borrowRate,
        uint256 defaultedDebt
    ) external override onlyMarket {
        require(!_paused, "Pool is paused");

        _asset.safeTransferFrom(from, address(this), amount);
        _updateCumulativeDebtBorrowRate(false, defaultedDebt, borrowRate);
        _debt -= defaultedDebt;
        _updateBorrowRate();
    }

    /// @notice Returns the current borrow rate.
    /// @return The current borrow rate.
    function getBorrowRate() external view override returns (uint256) {
        return _borrowRate;
    }

    /// @notice Updates the current borrow rate.
    function _updateBorrowRate() internal {
        _borrowRate = IInterestRate(
            IAddressesProvider(_addressProvider).getInterestRate()
        ).calculateBorrowRate(getUnderlyingBalance(), _debt);

        emit UpdatedBorrowRate(_borrowRate);
    }

    /// @notice Updates the cumulative debt borrow rate by adding or subtracting `amount` at `borrowRate`, depending on `increaseDebt`. If the debt reaches zero, the cumulative debt borrow rate is set to zero.
    /// @param increaseDebt Whether to increase or decrease the debt.
    /// @param amount The amount of debt to add or subtract.
    /// @param borrowRate The current borrow rate.
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

    /// @notice Returns the current supply rate.
    /// @return The current supply rate.
    function getSupplyRate() external view override returns (uint256) {
        uint256 supplyRate = 0;
        if (totalAssets() > 0) {
            supplyRate = (_cumulativeDebtBorrowRate * _debt) / totalAssets();
        }
        return supplyRate;
    }

    /// @notice Returns the current debt.
    /// @return The current debt.
    function getDebt() external view override returns (uint256) {
        return _debt;
    }

    /// @notice Returns the current utilization rate.
    /// @return The current utilization rate.
    function getUtilizationRate() external view override returns (uint256) {
        return
            IInterestRate(_addressProvider.getInterestRate())
                .calculateUtilizationRate(getUnderlyingBalance(), _debt);
    }

    /// @notice Sets the pool configuration.
    /// @param poolConfig The pool configuration to set
    function setPoolConfig(
        ConfigTypes.LendingPoolConfig memory poolConfig
    ) external onlyOwner {
        _lendingPoolConfig = poolConfig;
    }

    /// @notice Returns the current pool configuration.
    /// @return The current pool configuration.
    function getPoolConfig()
        external
        view
        returns (ConfigTypes.LendingPoolConfig memory)
    {
        return _lendingPoolConfig;
    }

    /// @notice Sets the pause state of the pool.
    /// @param paused Whether to pause the pool or not.
    function setPause(bool paused) external onlyOwner {
        _paused = paused;
    }
}
