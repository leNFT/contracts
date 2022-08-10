//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;

import {IERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";

interface IReserve is IERC20Upgradeable {
    function getAsset() external view returns (address);

    function getUnderlyingBalance() external view returns (uint256);

    function mint(address user, uint256 amount) external;

    function burn(address user, uint256 amount) external;

    function depositUnderlying(address depositor, uint256 amount) external;

    function withdrawUnderlying(address to, uint256 amount) external;

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

    function getMaximumWithdrawalAmount(address to)
        external
        view
        returns (uint256);

    function getBorrowRate() external view returns (uint256);

    function getUtilizationRate() external view returns (uint256);

    function getMaximumUtilizationRate() external view returns (uint256);

    function getLiquidationPenalty() external view returns (uint256);

    function getLiquidationFee() external view returns (uint256);

    function getUnderlyingSafeguard() external view returns (uint256);
}
