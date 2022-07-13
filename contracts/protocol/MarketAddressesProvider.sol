//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;

import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {IMarketAddressesProvider} from "../interfaces/IMarketAddressesProvider.sol";

contract MarketAddressesProvider is
    OwnableUpgradeable,
    IMarketAddressesProvider
{
    address private _marketAddress;
    address private _debtToken;
    address private _treasury;
    address private _feeTreasury;
    address private _loanCenter;
    address private _nftOracle;
    address private _interestRate;

    function setMarketAddress(address marketAddress)
        external
        override
        onlyOwner
    {
        _marketAddress = marketAddress;
    }

    function getMarketAddress() external view override returns (address) {
        return _marketAddress;
    }

    function setFeeTreasury(address feeTreasury) external override onlyOwner {
        _feeTreasury = feeTreasury;
    }

    function getFeeTreasury() external view override returns (address) {
        return _feeTreasury;
    }

    function setLoanCenter(address loanCenter) external override onlyOwner {
        _loanCenter = loanCenter;
    }

    function getLoanCenter() external view override returns (address) {
        return _loanCenter;
    }

    function setInterestRate(address interestRate) external override onlyOwner {
        _interestRate = interestRate;
    }

    function getInterestRate() external view override returns (address) {
        return _interestRate;
    }

    function setNFTOracle(address nftOracle) external override onlyOwner {
        _nftOracle = nftOracle;
    }

    function getNFTOracle() external view override returns (address) {
        return _nftOracle;
    }

    function setDebtToken(address debtToken) external override onlyOwner {
        _debtToken = debtToken;
    }

    function getDebtToken() external view override returns (address) {
        return _debtToken;
    }
}
