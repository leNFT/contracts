const { ethers } = require("hardhat");

let loadEnv = async function () {
  const ONE_DAY = 86400;
  console.log("Setting up enviroment...");

  [owner, addr1, addr2] = await ethers.getSigners();

  //Deploy libraries
  ValidationLogicLib = await ethers.getContractFactory("ValidationLogic");
  validationLogicLib = await ValidationLogicLib.deploy();
  console.log("Validation Logic Lib Address:", validationLogicLib.address);
  BorrowLogicLib = await ethers.getContractFactory("BorrowLogic", {
    libraries: {
      ValidationLogic: validationLogicLib.address,
    },
  });
  borrowLogicLib = await BorrowLogicLib.deploy();
  console.log("Borrow Logic Lib Address:", borrowLogicLib.address);
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
  addressesProvider = await upgrades.deployProxy(AddressesProvider);

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
      "25000000000000000000", // TVLSafeguard
      {
        liquidationPenalty: "1800", // defaultLiquidationPenalty
        liquidationFee: "200", // defaultProtocolLiquidationFee
        maximumUtilizationRate: "8500", // defaultMaximumUtilizationRate
      },
    ],
    { unsafeAllow: ["external-library-linking"], timeout: 0 }
  );

  // Deploy and initialize loan center provider proxy
  const LoanCenter = await ethers.getContractFactory("LoanCenter");
  const loanCenter = await upgrades.deployProxy(LoanCenter, [
    addressesProvider.address,
    "4000", // DefaultMaxCollaterization 40%
  ]);

  console.log("Deployed LoanCenter");

  // Deploy and initialize the debt token
  const DebtToken = await ethers.getContractFactory("DebtToken");
  const debtToken = await upgrades.deployProxy(DebtToken, [
    addressesProvider.address,
    "LDEBT TOKEN",
    "LDEBT",
  ]);

  console.log("Deployed DebtToken");

  // Deploy and initialize the native token
  const NativeToken = await ethers.getContractFactory("NativeToken");
  nativeToken = await upgrades.deployProxy(NativeToken, [
    addressesProvider.address,
    "leNFT Token",
    "LE",
    "100000000000000000000000000", //100M Max Cap
    "250000000000000000000000", //0.25M Max Airdrop Cap
    "0x91A7cEeAf399e9f933FF13F9575A2B74ac9c3EA7", // Dev Address
    "15000000000000000000000000", // 15M Dev Tokens
    ONE_DAY * 365 * 2, // 2-year dev vesting
    "20000000000000000000",
  ]);

  console.log("Deployed NativeToken");

  // Deploy and initialize Genesis NFT
  const GenesisNFT = await ethers.getContractFactory("GenesisNFT");
  genesisNFT = await upgrades.deployProxy(GenesisNFT, [
    addressesProvider.address,
    "leNFT Genesis",
    "LGEN",
    "9999",
    "3000000000000000",
    "250",
    50000000, // Native Token Mint Factor
    ONE_DAY * 120, // Max locktime (120 days in s)
    ONE_DAY * 14, // Min locktime (14 days in s)
    "0x91A7cEeAf399e9f933FF13F9575A2B74ac9c3EA7",
  ]);

  console.log("Deployed GenesisNFT");

  // Deploy and initialize Voting Escrow contract
  const VotingEscrow = await ethers.getContractFactory("VotingEscrow");
  votingEscrow = await upgrades.deployProxy(VotingEscrow, [
    addressesProvider.address,
  ]);

  console.log("Deployed VotingEscrow");

  // Deploy and initialize Gauge Controller
  const GaugeController = await ethers.getContractFactory("GaugeController");
  gaugeController = await upgrades.deployProxy(GaugeController, [
    addressesProvider.address,
  ]);

  console.log("Deployed GaugeController");

  // Deploy and initialize Fee distributor
  const FeeDistributor = await ethers.getContractFactory("FeeDistributor");
  const feeDistributor = await upgrades.deployProxy(FeeDistributor, [
    addressesProvider.address,
  ]);

  console.log("Deployed FeeDistributor");

  // Deploy and initialize Trading Pool Factory
  const TradingPoolFactory = await ethers.getContractFactory(
    "TradingPoolFactory"
  );
  tradingPoolFactory = await upgrades.deployProxy(TradingPoolFactory, [
    addressesProvider.address,
    "1000", // Default protocol fee (10%)
    "25000000000000000000", // TVLSafeguard
  ]);

  console.log("Deployed TradingPoolFactory");

  console.log("Deployed All Proxies");

  /****************************************************************
  DEPLOY NON-PROXY CONTRACTS
  Deploy contracts that are not updatable
  ******************************************************************/

  // Deploy the Interest Rate contract
  const InterestRate = await ethers.getContractFactory("InterestRate");
  const interestRate = await InterestRate.deploy(7000, 500, 2000, 20000);
  await interestRate.deployed();

  // Deploy the NFT Oracle contract
  const NFTOracle = await ethers.getContractFactory("NFTOracle");
  const nftOracle = await NFTOracle.deploy(addressesProvider.address);
  await nftOracle.deployed();

  // Deploy TokenOracle contract
  const TokenOracle = await ethers.getContractFactory("TokenOracle");
  const tokenOracle = await TokenOracle.deploy();
  await tokenOracle.deployed();

  // Deploy  Swap Router
  const SwapRouter = await ethers.getContractFactory("SwapRouter");
  const swapRouter = await SwapRouter.deploy(addressesProvider.address);

  console.log("Deployed SwapRouter");

  // Deploy WETH Gateway contract
  const WETHGateway = await ethers.getContractFactory("WETHGateway");
  wethGateway = await WETHGateway.deploy(addressesProvider.address);
  await wethGateway.deployed();

  // Deploy WETH contract
  const WETH = await ethers.getContractFactory("WETH");
  weth = await WETH.deploy();
  await weth.deployed();

  // Deploy Test NFT contracts
  const TestNFT = await ethers.getContractFactory("TestNFT");
  testNFT = await TestNFT.deploy("Test NFT", "TNFT");
  await testNFT.deployed();
  const TestNFT2 = await ethers.getContractFactory("TestNFT");
  testNFT2 = await TestNFT2.deploy("Test NFT2", "TNFT2");
  await testNFT2.deployed();

  // Deploy price curves contracts
  const ExponentialCurve = await ethers.getContractFactory(
    "ExponentialPriceCurve"
  );
  exponentialCurve = await ExponentialCurve.deploy();
  await exponentialCurve.deployed();
  const LinearCurve = await ethers.getContractFactory("LinearPriceCurve");
  linearCurve = await LinearCurve.deploy();
  await linearCurve.deployed();

  console.log("Deployed Non-Proxies");

  // Set all contracts in the addresses provider
  const setLendingMarketTx = await addressesProvider.setLendingMarket(
    lendingMarket.address
  );
  await setLendingMarketTx.wait();
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
  const setFeeDistributorTx = await addressesProvider.setFeeDistributor(
    feeDistributor.address
  );
  await setFeeDistributorTx.wait();
  const setNativeTokenTx = await addressesProvider.setNativeToken(
    nativeToken.address
  );
  await setNativeTokenTx.wait();
  const setLoanCenterTx = await addressesProvider.setLoanCenter(
    loanCenter.address
  );
  await setLoanCenterTx.wait();
  const setGenesisNFT = await addressesProvider.setGenesisNFT(
    genesisNFT.address
  );
  await setGenesisNFT.wait();
  const setVotingEscrowTx = await addressesProvider.setVotingEscrow(
    votingEscrow.address
  );
  await setVotingEscrowTx.wait();
  const setSwapRouterTx = await addressesProvider.setSwapRouter(
    swapRouter.address
  );
  await setSwapRouterTx.wait();
  const setTradingPoolFactoryTx = await addressesProvider.setTradingPoolFactory(
    tradingPoolFactory.address
  );
  await setTradingPoolFactoryTx.wait();
  const setGaugeCotrollerTx = await addressesProvider.setGaugeController(
    gaugeController.address
  );
  await setGaugeCotrollerTx.wait();
  const setWETHTx = await addressesProvider.setWETH(weth.address);
  await setWETHTx.wait();

  // Set trusted price source
  const setTrustedPriceSourceTx = await nftOracle.setTrustedPriceSigner(
    "0xfEa2AF8BB65c34ee64A005057b4C749310321Fa0",
    true
  );
  await setTrustedPriceSourceTx.wait();

  //Add a price to the native token using the token oracle
  const setNativeTokenPriceTx = await tokenOracle.setTokenETHPrice(
    nativeToken.address,
    "100000000000000" //0.0001 nativeToken/ETH
  );
  await setNativeTokenPriceTx.wait();

  //Add a price to test token ( test token = 1 weth)
  const setTestTokenPriceTx = await tokenOracle.setTokenETHPrice(
    weth.address,
    "1000000000000000000" //1 testToken/ETH
  );
  await setTestTokenPriceTx.wait();

  console.log("loaded");
};

function loadTest() {
  before(loadEnv);
}

exports.loadTest = loadTest;
exports.loadEnv = loadEnv;
