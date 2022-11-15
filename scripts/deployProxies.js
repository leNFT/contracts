// We require the Hardhat Runtime Environment explicitly here. This is optional
// but useful for running the script in a standalone fashion through `node <script>`.
//
// When running the script with `npx hardhat run <script>` you'll find the Hardhat
// Runtime Environment's members available in the global scope.
// const hre = require("hardhat");
require("dotenv").config();

async function main() {
  // Hardhat always runs the compile task when running scripts with its command
  // line interface.
  //
  // If this script is run directly using `node` you may want to call compile
  // manually to make sure everything is compiled
  // await hre.run('compile');
  let contractAddresses = require("../../lenft-interface/contractAddresses.json");
  let chainID = hre.network.config.chainId;
  let addresses = contractAddresses[chainID.toString(16)];
  const ONE_DAY = 86400;

  var feeTreasuryAddress;
  if (hre.network.config.chainId == 1) {
    feeTreasuryAddress = process.env.MAINNET_FEE_TREASURY;
  } else if (hre.network.config.chainId == 5) {
    feeTreasuryAddress = process.env.GOERLI_FEE_TREASURY;
  }

  var devAddress;
  if (hre.network.config.chainId == 1) {
    devAddress = process.env.MAINNET_DEV_ADDRESS;
  } else if (hre.network.config.chainId == 5) {
    devAddress = process.env.GOERLI_DEV_ADDRESS;
  }

  /****************************************************************
  DEPLOY LIBRARIES
  They will then be linked to the contracts that use them
  ******************************************************************/

  // Deploy validation logic lib
  ValidationLogicLib = await ethers.getContractFactory("ValidationLogic");
  validationLogicLib = await ValidationLogicLib.deploy();
  console.log("Validation Logic Lib Address:", validationLogicLib.address);

  // Deploy borrow logic lib
  BorrowLogicLib = await ethers.getContractFactory("BorrowLogic", {
    libraries: {
      ValidationLogic: validationLogicLib.address,
    },
  });
  borrowLogicLib = await BorrowLogicLib.deploy();
  console.log("Borrow Logic Lib Address:", borrowLogicLib.address);

  // Deploy liquidation logic lib
  LiquidationLogicLib = await ethers.getContractFactory("LiquidationLogic", {
    libraries: {
      ValidationLogic: validationLogicLib.address,
    },
  });
  liquidationLogicLib = await LiquidationLogicLib.deploy();
  console.log("Liquidation Logic Lib Address:", liquidationLogicLib.address);

  /****************************************************************
  DEPLOY PROXIES
  They will serve as an entry point for the upgraded contracts
  ******************************************************************/

  // Deploy and initialize addresses provider proxy
  const AddressesProvider = await ethers.getContractFactory(
    "AddressesProvider"
  );
  const addressesProvider = await upgrades.deployProxy(AddressesProvider);
  console.log("Addresses Provider Proxy Address:", addressesProvider.address);

  // Deploy and initialize market proxy
  const Market = await ethers.getContractFactory("Market", {
    libraries: {
      BorrowLogic: borrowLogicLib.address,
      LiquidationLogic: liquidationLogicLib.address,
      ValidationLogic: validationLogicLib.address,
    },
  });
  const market = await upgrades.deployProxy(
    Market,
    [
      addressesProvider.address,
      {
        liquidationPenalty: "1800", // defaultLiquidationPenalty
        protocolLiquidationFee: "200", // defaultProtocolLiquidationFee
        maximumUtilizationRate: "8500", // defaultMaximumUtilizationRate
        tvlSafeguard: "25000000000000000000", // defaultTVLSafeguard
      },
    ],
    { unsafeAllow: ["external-library-linking"], timeout: 0 }
  );
  console.log("Market Proxy Address:", market.address);

  // Deploy and initialize loan center provider proxy
  const LoanCenter = await ethers.getContractFactory("LoanCenter");
  const loanCenter = await upgrades.deployProxy(LoanCenter, [
    addressesProvider.address,
    "4000", // DefaultMaxCollaterization 40%
  ]);
  console.log("Loan Center Proxy Address:", loanCenter.address);

  // Deploy and initialize the debt token
  const DebtToken = await ethers.getContractFactory("DebtToken");
  const debtToken = await upgrades.deployProxy(DebtToken, [
    addressesProvider.address,
    "LDEBT TOKEN",
    "LDEBT",
  ]);
  console.log("Debt Token Proxy Address:", debtToken.address);

  // Deploy and initialize the native token
  const NativeToken = await ethers.getContractFactory("NativeToken");
  const nativeToken = await upgrades.deployProxy(NativeToken, [
    addressesProvider.address,
    "leNFT Token",
    "LE",
    "100000000000000000000000000", //100M Max Cap
    devAddress,
    "15000000000000000000000000", // 15M Dev Tokens
    ONE_DAY * 365 * 2, // 2-year dev vesting
  ]);
  console.log("Native Token Proxy Address:", nativeToken.address);

  // Deploy and initialize the native token vault
  const NativeTokenVault = await ethers.getContractFactory("NativeTokenVault", {
    libraries: {
      ValidationLogic: validationLogicLib.address,
    },
  });
  const nativeTokenVault = await upgrades.deployProxy(
    NativeTokenVault,
    [
      addressesProvider.address,
      "veleNFT Token",
      "veLE",
      nativeToken.address,
      {
        factor: "55000000000000000", // 0.055 Liquidation Reward Factor
        maxReward: "25000000000000000000000", // 25000 leNFT Reward Limit
        priceThreshold: 9000, // Liquidation Reward Price Threshold (90%)
        priceLimit: 12000, // Liquidation Reward Price Limit (120%)
      },
      {
        factor: "15000000000000000000", // 15 Boost Factor
        limit: 1500, //15% Boost Limit
      },
      {
        factor: "100000000000000000000000", // Staking Rewards Factor
        period: ONE_DAY * 7, // 7-day period between vault staking rewards
        maxPeriods: "416", // Limit number of staking periods
      },
      {
        coolingPeriod: ONE_DAY * 7, // 7-day cooling period
        activePeriod: ONE_DAY * 7, // 2-day active period
      },
    ],
    { unsafeAllow: ["external-library-linking"], timeout: 0 }
  );
  console.log("Native Token Vault Proxy Address:", nativeTokenVault.address);

  // Deploy and initialize Genesis NFT
  const GenesisNFT = await ethers.getContractFactory("GenesisNFT");
  const genesisNFT = await upgrades.deployProxy(GenesisNFT, [
    addressesProvider.address,
    "leNFT Genesis",
    "LGEN",
    "9999",
    "30000000000000000",
    "250",
    50000000, // Native Token Mint Factor
    ONE_DAY * 120, // Max locktime (120 days in s)
    ONE_DAY * 14, // Min locktime (14 days in s)
    devAddress,
  ]);
  console.log("Genesis NFT Proxy Address:", genesisNFT.address);

  /****************************************************************
  DEPLOY NON-PROXY CONTRACTS
  Deploy contracts that are not updatable
  ******************************************************************/

  // Deploy the Interest Rate contract
  const InterestRate = await ethers.getContractFactory("InterestRate");
  interestRate = await InterestRate.deploy(7000, 500, 2000, 20000);
  await interestRate.deployed();
  console.log("Interest Rate Address:", interestRate.address);

  // Deploy the NFT Oracle contract
  const NFTOracle = await ethers.getContractFactory("NFTOracle");
  nftOracle = await NFTOracle.deploy(addressesProvider.address);
  await nftOracle.deployed();
  console.log("NFT Oracle Address:", nftOracle.address);

  // Deploy TokenOracle contract
  const TokenOracle = await ethers.getContractFactory("TokenOracle");
  tokenOracle = await TokenOracle.deploy();
  await tokenOracle.deployed();
  console.log("Token Oracle Address:", tokenOracle.address);

  // Deploy WETH Gateway contract
  const WETHGateway = await ethers.getContractFactory("WETHGateway");
  wethGateway = await WETHGateway.deploy(addressesProvider.address);
  await wethGateway.deployed();
  console.log("WETHGateway Address:", wethGateway.address);

  /****************************************************************
  SETUP TRANSACTIONS
  Broadcast transactions whose purpose is to setup the protocol for use
  ******************************************************************/

  //Add a default price to the native token using the token oracle
  const setNativeTokenPriceTx = await tokenOracle.setTokenETHPrice(
    nativeToken.address,
    "100000000000000" //0.0001 nativeToken/ETH
  );
  await setNativeTokenPriceTx.wait();
  console.log("Set Native Token / ETH to 0.0001");

  //Set every address in the address provider
  const setMarketTx = await addressesProvider.setMarket(market.address);
  await setMarketTx.wait();
  const setDebtTokenTx = await addressesProvider.setDebtToken(
    debtToken.address
  );
  await setDebtTokenTx.wait();
  const setInterestRateTx = await addressesProvider.setInterestRate(
    interestRate.address
  );
  await setInterestRateTx.wait();
  const setNFTOracleTx = await addressesProvider.setNFTOracle(
    nftOracle.address
  );
  await setNFTOracleTx.wait();
  const setTokenOracleTx = await addressesProvider.setTokenOracle(
    tokenOracle.address
  );
  await setTokenOracleTx.wait();
  const setLoanCenterTx = await addressesProvider.setLoanCenter(
    loanCenter.address
  );
  await setLoanCenterTx.wait();
  const setNativeTokenVaultTx = await addressesProvider.setNativeTokenVault(
    nativeTokenVault.address
  );
  await setNativeTokenVaultTx.wait();
  const setNativeTokenTx = await addressesProvider.setNativeToken(
    nativeToken.address
  );
  await setNativeTokenTx.wait();
  const setGenesisNFT = await addressesProvider.setGenesisNFT(
    genesisNFT.address
  );
  await setGenesisNFT.wait();
  const setFeeTreasuryTx = await addressesProvider.setFeeTreasury(
    feeTreasuryAddress
  );
  await setFeeTreasuryTx.wait();
  const setWETHTx = await addressesProvider.setWETH(addresses["ETH"].address);
  await setWETHTx.wait();
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
