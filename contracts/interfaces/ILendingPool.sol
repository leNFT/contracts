//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface ILendingPool is IERC20 {
    function getUnderlyingBalance() external view returns (uint256);

    function transferUnderlying(
        address to,
        uint256 amount,
        uint256 borrowRate
    ) external;

    function receiveUnderlying(
        address from,
        uint256 amount,
        uint256 borrowRate,
        uint256 interest
    ) external;

    function receiveUnderlyingDefaulted(
        address from,
        uint256 amount,
        uint256 borrowRate,
        uint256 defaultedDebt
    ) external;

    function getSupplyRate() external view returns (uint256);

    function getDebt() external view returns (uint256);

    function getBorrowRate() external view returns (uint256);

    function getUtilizationRate() external view returns (uint256);

    function getMaximumUtilizationRate() external view returns (uint256);

    function getLiquidationPenalty() external view returns (uint256);

    function getLiquidationFee() external view returns (uint256);

    function getTVLSafeguard() external view returns (uint256);
}