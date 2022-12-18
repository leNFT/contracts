//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;

interface IAddressesProvider {
    function setLendingMarket(address market) external;

    function getLendingMarket() external view returns (address);

    function setTradingPoolFactory(address tradingPoolFactory) external;

    function getTradingPoolFactory() external view returns (address);

    function setGaugeController(address gaugeController) external;

    function getGaugeController() external view returns (address);

    function setLoanCenter(address loancenter) external;

    function getLoanCenter() external view returns (address);

    function setVotingEscrow(address nativeTokenVault) external;

    function getVotingEscrow() external view returns (address);

    function setNativeToken(address nativeToken) external;

    function getNativeToken() external view returns (address);

    function setInterestRate(address interestRate) external;

    function getInterestRate() external view returns (address);

    function setNFTOracle(address nftOracle) external;

    function getNFTOracle() external view returns (address);

    function setTokenOracle(address tokenOracle) external;

    function getTokenOracle() external view returns (address);

    function setFeeDistributor(address feeDistributor) external;

    function getFeeDistributor() external view returns (address);

    function setLiquidationRewards(address liquidationRewards) external;

    function getLiquidationRewards() external view returns (address);

    function setDebtToken(address debtToken) external;

    function getDebtToken() external view returns (address);

    function getWETH() external view returns (address);

    function setWETH(address weth) external;

    function setGenesisNFT(address genesisNFT) external;

    function getGenesisNFT() external view returns (address);
}
