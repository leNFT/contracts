//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;

import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {IAddressesProvider} from "../interfaces/IAddressesProvider.sol";

contract AddressesProvider is OwnableUpgradeable, IAddressesProvider {
    address private _market;
    address private _debtToken;
    address private _treasury;
    address private _feeTreasury;
    address private _loanCenter;
    address private _nftOracle;
    address private _tokenOracle;
    address private _interestRate;
    address private _nativeTokenVault;
    address private _nativeToken;
    address private _weth;
    address private _genesisNFT;

    function initialize() external initializer {
        __Ownable_init();
    }

    function setMarket(address market) external override onlyOwner {
        _market = market;
    }

    function getMarket() external view override returns (address) {
        return _market;
    }

    function setNativeTokenVault(address nativeTokenVault)
        external
        override
        onlyOwner
    {
        _nativeTokenVault = nativeTokenVault;
    }

    function getNativeTokenVault() external view override returns (address) {
        return _nativeTokenVault;
    }

    function setNativeToken(address nativeToken) external override onlyOwner {
        _nativeToken = nativeToken;
    }

    function getNativeToken() external view override returns (address) {
        return _nativeToken;
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

    function setTokenOracle(address tokenOracle) external override onlyOwner {
        _tokenOracle = tokenOracle;
    }

    function getTokenOracle() external view override returns (address) {
        return _tokenOracle;
    }

    function setDebtToken(address debtToken) external override onlyOwner {
        _debtToken = debtToken;
    }

    function getDebtToken() external view override returns (address) {
        return _debtToken;
    }

    function setWETH(address weth) external override onlyOwner {
        _weth = weth;
    }

    function getWETH() external view override returns (address) {
        return _weth;
    }

    function setGenesisNFT(address genesisNFT) external override onlyOwner {
        _genesisNFT = genesisNFT;
    }

    function getGenesisNFT() external view override returns (address) {
        return _genesisNFT;
    }
}
