// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.8.15;

import {IMarketAddressesProvider} from "../../interfaces/IMarketAddressesProvider.sol";

library LockLogic {
    function lock(
        IMarketAddressesProvider addressesProvider,
        uint256 amount,
        address collection
    ) external {}

    function unlock(
        IMarketAddressesProvider addressesProvider,
        uint256 amount,
        address collection
    ) external {}
}
