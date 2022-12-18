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
  var contractAddresses = require("../../lenft-interface/contractAddresses.json");
  let chainID = hre.network.config.chainId;
  console.log("chainID: ", chainID);
  var addresses = contractAddresses[chainID.toString(16)];
  const ONE_DAY = 86400;

  var devAddress;
  if (chainID == 1) {
    devAddress = process.env.MAINNET_DEV_ADDRESS;
  } else if (chainID == 5) {
    devAddress = process.env.GOERLI_DEV_ADDRESS;
  }

  /****************************************************************
  DEPLOY LIBRARIES
  They will then be linked to the contracts that use them
  ******************************************************************/

  // Deploy validation logic lib
  ValidationLogicLib = await ethers.getContractFactory("ValidationLogic");
  validationLogicLib = await ValidationLogicLib.deploy();
  addresses["ValidationLogicLib"] = validationLogicLib.address;

  // Deploy borrow logic lib
  BorrowLogicLib = await ethers.getContractFactory("BorrowLogic", {
    libraries: {
      ValidationLogic: validationLogicLib.address,
    },
  });
  borrowLogicLib = await BorrowLogicLib.deploy();
  addresses["BorrowLogicLib"] = borrowLogicLib.address;

  // Deploy liquidation logic lib
  LiquidationLogicLib = await ethers.getContractFactory("LiquidationLogic", {
    libraries: {
      ValidationLogic: validationLogicLib.address,
    },
  });
  liquidationLogicLib = await LiquidationLogicLib.deploy();
  addresses["LiquidationLogicLib"] = liquidationLogicLib.address;

  /****************************************************************
  DEPLOY PROXIES
  They will serve as an entry point for the upgraded contracts
  ******************************************************************/

  // Deploy and initialize addresses provider proxy
  const AddressesProvider = await ethers.getContractFactory(
    "AddressesProvider"
  );
  const addressesProvider = await upgrades.deployProxy(AddressesProvider);
  addresses["AddressesProvider"] = addressesProvider.address;

  // Deploy and initialize market proxy
  const LendingMarket = await ethers.getContractFactory("LendingMarket", {
    libraries: {
      BorrowLogic: borrowLogicLib.address,
      LiquidationLogic: liquidationLogicLib.address,
      ValidationLogic: validationLogicLib.address,
    },
  });
  const lendingMarket = await upgrades.deployProxy(
    LendingMarket,
    [
      addressesProvider.address,
      {
        liquidationPenalty: "1800", // defaultLiquidationPenalty
        liquidationFee: "200", // defaultProtocolLiquidationFee
        maximumUtilizationRate: "8500", // defaultMaximumUtilizationRate
        tvlSafeguard: "25000000000000000000", // defaultTVLSafeguard
      },
    ],
    { unsafeAllow: ["external-library-linking"], timeout: 0 }
  );
  addresses["LendingMarket"] = lendingMarket.address;

  // Deploy and initialize loan center provider proxy
  const LoanCenter = await ethers.getContractFactory("LoanCenter");
  const loanCenter = await upgrades.deployProxy(LoanCenter, [
    addressesProvider.address,
    "4000", // DefaultMaxCollaterization 40%
  ]);
  addresses["LoanCenter"] = loanCenter.address;

  // Deploy and initialize the debt token
  const DebtToken = await ethers.getContractFactory("DebtToken");
  const debtToken = await upgrades.deployProxy(DebtToken, [
    addressesProvider.address,
    "LDEBT TOKEN",
    "LDEBT",
  ]);
  addresses["DebtToken"] = debtToken.address;

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
    "20000000000000000000",
  ]);
  addresses["NativeToken"] = nativeToken.address;

  // Deploy and initialize the native token vault
  const LiquidationsRewards = await ethers.getContractFactory(
    "LiquidationRewards"
  );
  const liquidationsRewards = await upgrades.deployProxy(
    LiquidationsRewards,
    [
      addressesProvider.address,
      {
        factor: "55000000000000000", // 0.055 Liquidation Reward Factor
        maxReward: "25000000000000000000000", // 25000 leNFT Reward Limit
        priceThreshold: 9000, // Liquidation Reward Price Threshold (90%)
        priceLimit: 12000, // Liquidation Reward Price Limit (120%)
      },
    ],
    { unsafeAllow: ["external-library-linking"], timeout: 0 }
  );
  addresses["LiquidationsRewards"] = liquidationsRewards.address;

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
  addresses["GenesisNFT"] = genesisNFT.address;

  // Deploy and initialize Voting Escrow contract
  const VotingEscrow = await ethers.getContractFactory("VotingEscrow");
  const votingEscrow = await upgrades.deployProxy(VotingEscrow, [
    addressesProvider.address,
  ]);
  addresses["VotingEscrow"] = votingEscrow.address;

  // Deploy and initialize Gauge Controller
  const GaugeController = await ethers.getContractFactory("GaugeController");
  const gaugeController = await upgrades.deployProxy(GaugeController, [
    addressesProvider.address,
  ]);
  addresses["GaugeController"] = gaugeController.address;

  // Deploy and initialize Fee distributor
  const FeeDistributor = await ethers.getContractFactory("FeeDistributor");
  const feeDistributor = await upgrades.deployProxy(FeeDistributor, [
    addressesProvider.address,
  ]);
  addresses["FeeDistributor"] = feeDistributor.address;

  // Deploy and initialize Trading Pool Factory
  const TradingPoolFactory = await ethers.getContractFactory(
    "TradingPoolFactory"
  );
  const tradingPoolFactory = await upgrades.deployProxy(TradingPoolFactory, [
    addressesProvider.address,
    "300", // Default swap fee (3%)
  ]);
  addresses["TradingPoolFactory"] = tradingPoolFactory.address;

  /****************************************************************
  DEPLOY NON-PROXY CONTRACTS
  Deploy contracts that are not updatable
  ******************************************************************/

  // Deploy the Interest Rate contract
  const InterestRate = await ethers.getContractFactory("InterestRate");
  interestRate = await InterestRate.deploy(7000, 500, 2000, 20000);
  await interestRate.deployed();
  addresses["InterestRate"] = interestRate.address;

  // Deploy the NFT Oracle contract
  const NFTOracle = await ethers.getContractFactory("NFTOracle");
  nftOracle = await NFTOracle.deploy(addressesProvider.address);
  await nftOracle.deployed();
  addresses["NFTOracle"] = nftOracle.address;

  // Deploy TokenOracle contract
  const TokenOracle = await ethers.getContractFactory("TokenOracle");
  tokenOracle = await TokenOracle.deploy();
  await tokenOracle.deployed();
  addresses["TokenOracle"] = tokenOracle.address;

  // Deploy WETH Gateway contract
  const WETHGateway = await ethers.getContractFactory("WETHGateway");
  wethGateway = await WETHGateway.deploy(addressesProvider.address);
  await wethGateway.deployed();
  addresses["WETHGateway"] = wethGateway.address;

  /****************************************************************
  SAVE TO DISK
  Write contract addresses to file
  ******************************************************************/

  var fs = require("fs");
  contractAddresses[chainID.toString(16)] = addresses;
  fs.writeFileSync(
    "../lenft-interface/contractAddresses.json",
    JSON.stringify(contractAddresses),
    function (err) {
      if (err) throw err;
      console.log("File written to interface folder");
    }
  );
  fs.writeFileSync(
    "../lenft-nft-api/contractAddresses.json",
    JSON.stringify(contractAddresses),
    function (err) {
      if (err) throw err;
      console.log("File written to API folder");
    }
  );

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
  const setLendingMarketTx = await addressesProvider.setLendingMarket(
    lendingMarket.address
  );
  await setLendingMarketTx.wait();
  const setTradingPoolFactoryTx = await addressesProvider.setTradingPoolFactory(
    tradingPoolFactory.address
  );
  await setTradingPoolFactoryTx.wait();
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
  const setLiquidationRewardsTx = await addressesProvider.setLiquidationRewards(
    liquidationsRewards.address
  );
  await setLiquidationRewardsTx.wait();
  const setNativeTokenTx = await addressesProvider.setNativeToken(
    nativeToken.address
  );
  await setNativeTokenTx.wait();
  const setGenesisNFT = await addressesProvider.setGenesisNFT(
    genesisNFT.address
  );
  await setGenesisNFT.wait();
  const setFeeDistributorTx = await addressesProvider.setFeeDistributor(
    feeDistributor.address
  );
  await setFeeDistributorTx.wait();
  const setGaugeControllerTx = await addressesProvider.setGaugeController(
    gaugeController.address
  );
  await setGaugeControllerTx.wait();
  const setVotingEscrowTx = await addressesProvider.setVotingEscrow(
    votingEscrow.address
  );
  await setVotingEscrowTx.wait();
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
