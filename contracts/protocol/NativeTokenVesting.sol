// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.8.17;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IAddressesProvider} from "../interfaces/IAddressesProvider.sol";
import {DataTypes} from "../libraries/types/DataTypes.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract NativeTokenVesting is Ownable {
    IAddressesProvider private _addressProvider;

    mapping(address => DataTypes.VestingParams) private _vested;
    mapping(address => uint256) _withdrawn;

    using SafeERC20 for IERC20;

    constructor(IAddressesProvider addressProvider) {
        _addressProvider = addressProvider;
    }

    /// @notice Gets the vesting parameters for the specified account
    /// @param account The address to get the vesting parameters for
    /// @return The vesting parameters for the specified address
    function getVesting(
        address account
    ) external view returns (DataTypes.VestingParams memory) {
        return _vested[account];
    }

    /// @notice Sets the vesting parameters for the specified account
    /// @param account The address to set the vesting parameters for
    /// @param period The vesting period in seconds
    /// @param cliff The cliff period in seconds
    /// @param amount The amount of tokens to vest
    function addVesting(
        address account,
        uint256 period,
        uint256 cliff,
        uint256 amount
    ) external onlyOwner {
        _vested[account] = DataTypes.VestingParams(
            block.timestamp,
            period,
            cliff,
            amount
        );
    }

    /// @notice Returns the amount of unvested tokens that can be withdrawn by the specified account.
    /// @param account The address to get the amount of unvested tokens that can be withdrawn for
    /// @return The amount of unvested tokens that can be withdrawn by the specified account
    function getAvailableToWithdraw(
        address account
    ) public view returns (uint256) {
        DataTypes.VestingParams memory vestingParams = _vested[account];
        uint256 unvestedTokens;

        // If the vesting period has passed
        if (block.timestamp > vestingParams.timestamp + vestingParams.period) {
            // If we are still in the cliff period
            if (
                block.timestamp <
                vestingParams.timestamp +
                    vestingParams.period +
                    vestingParams.cliff
            ) {
                unvestedTokens =
                    (vestingParams.amount *
                        (block.timestamp -
                            (vestingParams.timestamp + vestingParams.period))) /
                    vestingParams.cliff;
            } else {
                unvestedTokens = vestingParams.amount;
            }
            return unvestedTokens - _withdrawn[account];
        } else {
            return 0;
        }
    }

    function withdraw(uint256 amount) external {
        require(
            getAvailableToWithdraw(_msgSender()) >= amount,
            "Amount bigger than allowed by vesting"
        );
        _withdrawn[_msgSender()] += amount;
        IERC20(_addressProvider.getNativeToken()).safeTransfer(
            _msgSender(),
            amount
        );
    }
}
