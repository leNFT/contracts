//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;

interface IMarketAddressesProvider {
    function setMarketAddress(address market) external;

    function getMarketAddress() external view returns (address);

    function setLoanCenter(address loancenter) external;

    function getLoanCenter() external view returns (address);

    function setInterestRate(address interestRate) external;

    function getInterestRate() external view returns (address);

    function setNFTOracle(address nftOracle) external;

    function getNFTOracle() external view returns (address);

    function setFeeTreasury(address feeTreasury) external;

    function getFeeTreasury() external view returns (address);

    function setDebtToken(address debtToken) external;

    function getDebtToken() external view returns (address);
}
