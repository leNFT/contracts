//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;

interface ICurvePool {
    function get_balances() external view returns (uint256[2] memory);

    function add_liquidity(
        uint256[2] memory amounts,
        uint256 min_mint_amount
    ) external payable returns (uint256);

    function remove_liquidity_one_coin(
        uint256 _burn_amount,
        uint128 i,
        uint256 _min_received
    ) external returns (uint256);
}
