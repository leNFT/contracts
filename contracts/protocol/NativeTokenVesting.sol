// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.8.19;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IAddressProvider} from "../interfaces/IAddressProvider.sol";
import {DataTypes} from "../libraries/types/DataTypes.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {INativeToken} from "../interfaces/INativeToken.sol";

/// @title NativeTokenVesting
/// @author leNFT
/// @notice Contract that allows to set vesting parameters for a specified account
/// @dev Provides functionality for vesting tokens and defines a cap on the amount of tokens that can be vested
contract NativeTokenVesting is Ownable {
    uint256 private constant VESTING_CAP = 4e26; // 400M Vesting Cap (175M Team + 175M Treasury + 50M Liquidity Mining)
    uint256 private constant MIN_CLIFF_PERIOD = 1 weeks; // TESTNET: 0 weeks
    IAddressProvider private immutable _addressProvider;
    mapping(address => DataTypes.VestingParams) private _vestingParams;
    mapping(address => uint256) private _withdrawn;
    uint256 private _totalWithdrawn;

    event VestingWithdrawn(address indexed account, uint256 amount);
    event VestingAdded(
        address indexed account,
        uint256 period,
        uint256 cliff,
        uint256 amount
    );

    using SafeERC20 for IERC20;

    /// @notice Constructor
    /// @param addressProvider Address of the addressProvider contract
    constructor(IAddressProvider addressProvider) {
        _addressProvider = addressProvider;
    }

    /// @notice Gets the maximum supply of the vesting token
    /// @return The maximum supply of the vesting token
    function getVestingCap() public pure returns (uint256) {
        return VESTING_CAP;
    }

    /// @notice Gets the vesting parameters for the specified account
    /// @param account The address to get the vesting parameters for
    /// @return The vesting parameters for the specified address
    function getVesting(
        address account
    ) external view returns (DataTypes.VestingParams memory) {
        return _vestingParams[account];
    }

    /// @notice Sets the vesting parameters for the specified account
    /// @param account The address to set the vesting parameters for
    /// @param period The vesting period in seconds
    /// @param cliff The cliff period in seconds
    /// @param amount The amount of tokens to vest
    function setVesting(
        address account,
        uint256 period,
        uint256 cliff,
        uint256 amount
    ) external onlyOwner {
        require(cliff >= MIN_CLIFF_PERIOD, "NTV:SV:CLIFF_TOO_LOW");
        require(amount > 0, "NTV:SV:AMOUNT_0");
        _vestingParams[account] = DataTypes.VestingParams(
            block.timestamp,
            period,
            cliff,
            amount
        );
        // Reset the withdrawn amount in case we are updating vesting parameters
        delete _withdrawn[account];

        emit VestingAdded(account, period, cliff, amount);
    }

    /// @notice Returns the amount of unvested tokens that can be withdrawn by the specified account.
    /// @param account The address to get the amount of unvested tokens that can be withdrawn for
    /// @return The amount of unvested tokens that can be withdrawn by the specified account
    function getAvailableToWithdraw(
        address account
    ) public view returns (uint256) {
        DataTypes.VestingParams memory vestingParams = _vestingParams[account];
        uint256 unvestedTokens;

        // If the cliff period has passed
        if (block.timestamp > vestingParams.timestamp + vestingParams.cliff) {
            // If we are still in the vesting period
            if (
                block.timestamp <
                vestingParams.timestamp +
                    vestingParams.period +
                    vestingParams.cliff
            ) {
                unvestedTokens =
                    (vestingParams.amount *
                        (block.timestamp - vestingParams.timestamp)) /
                    (vestingParams.cliff + vestingParams.period);
            } else {
                unvestedTokens = vestingParams.amount;
            }
            return unvestedTokens - _withdrawn[account];
        }

        return 0;
    }

    /// @notice Withdraws the specified amount of unvested tokens
    /// @param amount The amount of unvested tokens to withdraw
    function withdraw(uint256 amount) external {
        require(
            getAvailableToWithdraw(msg.sender) >= amount,
            "NTV:W:AMOUNT_TOO_HIGH"
        );
        require(
            _totalWithdrawn + amount <= VESTING_CAP,
            "NTV:W:VESTING_CAP_REACHED"
        );
        _withdrawn[msg.sender] += amount;
        _totalWithdrawn += amount;
        INativeToken(_addressProvider.getNativeToken()).mintVestingTokens(
            msg.sender,
            amount
        );

        emit VestingWithdrawn(msg.sender, amount);
    }
}
