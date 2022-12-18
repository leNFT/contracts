// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.8.17;

/**
 * @title Time library
 * @author leNFT
 * @notice Provides time constants
 **/
library Time {
    uint256 internal constant DAY = 86400;
    uint256 internal constant WEEK = 7 * DAY;
    uint256 internal constant YEAR = 365 * DAY;
    uint256 internal constant YEAR_IN_WEEKS = 52;
}
