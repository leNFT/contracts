// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.8.17;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IAddressesProvider} from "../interfaces/IAddressesProvider.sol";

contract NativeTokenVesting is Ownable {
    IAddressesProvider private _addressProvider;

    constructor(IAddressesProvider addressProvider) {
        _addressProvider = addressProvider;
    }
}
