// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.8.19;

library SafeCast {
    function toUint40(uint256 value) internal pure returns (uint40) {
        require(value <= type(uint40).max, "SC:CAST_OVERFLOW");
        return uint40(value);
    }

    function toUint16(uint256 value) internal pure returns (uint16) {
        require(value <= type(uint16).max, "SC:CAST_OVERFLOW");
        return uint16(value);
    }
}
