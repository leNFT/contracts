// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.8.17;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IAddressesProvider} from "../interfaces/IAddressesProvider.sol";

contract NativeTokenVesting is Ownable {
    IAddressesProvider private _addressProvider;

    constructor(IAddressesProvider addressProvider) {
        _addressProvider = addressProvider;
    }

    /// @notice Returns the amount of unvested developer reward tokens.
    /// @return The amount of unvested developer reward tokens.
    function getDevRewardTokens() public view returns (uint256) {
        // uint256 unvestedTokens;
        // if (block.timestamp - _deployTimestamp < _devVestingTime) {
        //     unvestedTokens = ((_devReward *
        //         (block.timestamp - _deployTimestamp)) / _devVestingTime);
        // } else {
        //     unvestedTokens = _devReward;
        // }
        // return unvestedTokens - _devWithdrawn;
    }

    /// @notice Mints the specified amount of developer reward tokens to the developer address.
    /// @dev The caller must be the developer.
    /// @dev The amount must be less than or equal to the unvested developer reward tokens.
    /// @param amount The amount of developer reward tokens to mint.
    function mintDevRewardTokens(uint256 amount) external {
        // Require that the caller is the developer
        // require(_msgSender() == _devAddress, "Caller must be dev");
        // //Should only be able to withdrawn unvested tokens
        // require(
        //     getDevRewardTokens() >= amount,
        //     "Amount bigger than allowed by vesting"
        // );
        // _mintTokens(_devAddress, amount);
        // _devWithdrawn += amount;
    }
}
