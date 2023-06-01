// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.8.19;

/// @title SafeCast library
/// @author leNFT
/// @notice Casting utilities
/// @dev This library is used to safely cast between uint256 and smaller sized unsigned integers
library SafeCast {
    /// @notice Cast a uint256 to a uint40, revert on overflow
    /// @param value The uint256 value to be casted
    /// @return The uint40 value casted from uint256
    function toUint40(uint256 value) internal pure returns (uint40) {
        require(value <= type(uint40).max, "SC:CAST_OVERFLOW");
        return uint40(value);
    }

    /// @notice Cast a uint256 to a uint32, revert on overflow
    /// @param value The uint256 value to be casted
    /// @return The uint32 value casted from uint256
    function toUint16(uint256 value) internal pure returns (uint16) {
        require(value <= type(uint16).max, "SC:CAST_OVERFLOW");
        return uint16(value);
    }
}
