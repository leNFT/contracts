const { ethers } = require("hardhat");
const helpers = require("@nomicfoundation/hardhat-network-helpers");
require("dotenv").config();
const { priceSigner } = require("./getPriceSig.js");
const { time } = require("@nomicfoundation/hardhat-network-helpers");

let loadEnv = async function (isMainnetFork) {
  //Reset the fork if it's genesis
  console.log("isMainnetFork", isMainnetFork);
  if (isMainnetFork) {
    console.log("Resetting the mainnet fork...");
    await helpers.reset(
      "https://mainnet.infura.io/v3/" + process.env.INFURA_API_KEY,
      17253963 // Block number 13/05/2023
    );
  } else {
    console.log("Resetting the local fork...");
    await helpers.reset();
    console.log("Resetted the local fork");
  }

  const ONE_DAY = 86400;
  console.log("Setting up enviroment...");

  [owner, address1] = await ethers.getSigners();

  // Mainnet weth address
  if (isMainnetFork) {
    // Get the WETH from the mainnet fork
    console.log("Getting WETH from the mainnet fork...");
    wethAddress = "0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2";
    weth = await ethers.getContractAt(
      "contracts/interfaces/IWETH.sol:IWETH",
      wethAddress
    );
    console.log("Got WETH from the mainnet fork:", wethAddress);
  } else {
    // Deploy a WETH contract
    console.log("Deploying WETH...");
    const WETH = await ethers.getContractFactory("WETH");
    weth = await WETH.deploy();
    await weth.deployed();
    wethAddress = weth.address;
    console.log("Deployed WETH:", wethAddress);
  }

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
  const AddressProvider = await ethers.getContractFactory("AddressProvider");
  addressProvider = await upgrades.deployProxy(AddressProvider);

  console.log("Deployed addressProvider");

  // Deploy and initialize market proxy
  const LendingMarket = await ethers.getContractFactory("LendingMarket", {
    libraries: {
      BorrowLogic: borrowLogicLib.address,
      LiquidationLogic: liquidationLogicLib.address,
      ValidationLogic: validationLogicLib.address,
    },
  });
  lendingMarket = await upgrades.deployProxy(
    LendingMarket,
    [
      addressProvider.address,
      "25000000000000000000", // TVLSafeguard
      {
        maxLiquidatorDiscount: "2000", // maxLiquidatorDiscount
        auctioneerFee: "50", // defaultauctioneerFee
        liquidationFee: "200", // defaultProtocolLiquidationFee
        maxUtilizationRate: "8500", // defaultmaxUtilizationRate
      },
    ],
    { unsafeAllow: ["external-library-linking"], timeout: 0 }
  );

  console.log("Deployed LendingMarket");

  // Deploy and initialize loan center provider proxy
  const LoanCenter = await ethers.getContractFactory("LoanCenter");
  loanCenter = await upgrades.deployProxy(LoanCenter, [
    addressProvider.address,
    {
      maxLTV: "3000", // DefaultMaxCollaterization 30%
      liquidationThreshold: "6000", // DefaultLiquidationThreshold 60%
    },
  ]);

  console.log("Deployed LoanCenter");

  // Deploy and initialize the native token
  const NativeToken = await ethers.getContractFactory("NativeToken");
  nativeToken = await upgrades.deployProxy(NativeToken, [
    addressProvider.address,
  ]);

  console.log("Deployed NativeToken");

  // Deploy and initialize Genesis NFT
  const GenesisNFT = await ethers.getContractFactory("GenesisNFT");
  genesisNFT = await upgrades.deployProxy(GenesisNFT, [
    addressProvider.address,
    "250", // 2.5% LTV Boost for Genesis NFT
    address1.address,
  ]);

  console.log("Deployed GenesisNFT");

  // Deploy and initialize the Bribes contract
  const Bribes = await ethers.getContractFactory("Bribes");
  bribes = await upgrades.deployProxy(Bribes, [addressProvider.address]);

  console.log("Deployed Bribes");

  // Deploy and initialize Voting Escrow contract
  console.log("addressProvider.address", addressProvider.address);
  const VotingEscrow = await ethers.getContractFactory("VotingEscrow");
  votingEscrow = await upgrades.deployProxy(VotingEscrow, [
    addressProvider.address,
  ]);

  console.log("Deployed VotingEscrow");

  // Deploy and initialize Gauge Controller
  const GaugeController = await ethers.getContractFactory("GaugeController");
  gaugeController = await upgrades.deployProxy(GaugeController, [
    addressProvider.address,
    "280000000000000000000", // Initial epoch rewards
    6 * 7 * 24 * 3600, // LP Maturation Period in seconds (set to 6 weeks)
  ]);

  console.log("Deployed GaugeController");

  // Deploy and initialize Fee distributor
  const FeeDistributor = await ethers.getContractFactory("FeeDistributor");
  feeDistributor = await upgrades.deployProxy(FeeDistributor, [
    addressProvider.address,
  ]);

  console.log("Deployed FeeDistributor");

  // Deploy and initialize Trading Pool Factory
  const TradingPoolFactory = await ethers.getContractFactory(
    "TradingPoolFactory"
  );
  tradingPoolFactory = await upgrades.deployProxy(TradingPoolFactory, [
    addressProvider.address,
    "1000", // Default protocol fee (10%)
    "25000000000000000000", // TVLSafeguard
  ]);

  console.log("Deployed TradingPoolFactory");

  console.log("Deployed All Proxies");

  /****************************************************************
  DEPLOY NON-PROXY CONTRACTS
  Deploy contracts that are not updatable
  ******************************************************************/

  // Deploy liquidity position metadata contract
  const LiquidityPairMetadata = await ethers.getContractFactory(
    "LiquidityPairMetadata"
  );
  liquidityPairMetadata = await LiquidityPairMetadata.deploy();
  await liquidityPairMetadata.deployed();

  // Deploy the trading pool helper contract
  const TradingPoolHelpers = await ethers.getContractFactory(
    "TradingPoolHelpers"
  );
  tradingPoolHelpers = await TradingPoolHelpers.deploy(addressProvider.address);
  await tradingPoolHelpers.deployed();

  // Deploy the Interest Rate contract
  const InterestRate = await ethers.getContractFactory("InterestRate");
  interestRate = await InterestRate.deploy();
  await interestRate.deployed();

  // Deploy the NFT Oracle contract
  const NFTOracle = await ethers.getContractFactory("NFTOracle");
  nftOracle = await NFTOracle.deploy();
  await nftOracle.deployed();

  // Deploy TokenOracle contract
  const TokenOracle = await ethers.getContractFactory("TokenOracle");
  tokenOracle = await TokenOracle.deploy();
  await tokenOracle.deployed();

  // Deploy  Swap Router
  const SwapRouter = await ethers.getContractFactory("SwapRouter");
  swapRouter = await SwapRouter.deploy(addressProvider.address);

  console.log("Deployed SwapRouter");

  // Deploy WETH Gateway contract
  const WETHGateway = await ethers.getContractFactory("WETHGateway");
  wethGateway = await WETHGateway.deploy(addressProvider.address, wethAddress);
  await wethGateway.deployed();

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

  // Deploy the vesting contract
  const NativeTokenVesting = await ethers.getContractFactory(
    "NativeTokenVesting"
  );
  nativeTokenVesting = await NativeTokenVesting.deploy(
    addressProvider.address,
    "40000000000000000000000000" // 40M Vesting Cap (17.5M Team + 17.5M Treasury + 5M Liquidity Mining)
  );
  await nativeTokenVesting.deployed();

  console.log("Deployed Non-Proxies");

  // Set all contracts in the addresses provider
  const setLendingMarketTx = await addressProvider.setLendingMarket(
    lendingMarket.address
  );
  await setLendingMarketTx.wait();

  const setLiquidityPairMetadataTx =
    await addressProvider.setLiquidityPairMetadata(
      liquidityPairMetadata.address
    );
  await setLiquidityPairMetadataTx.wait();
  const setInterestRateTx = await addressProvider.setInterestRate(
    interestRate.address
  );
  await setInterestRateTx.wait();
  const setNFTOracleTx = await addressProvider.setNFTOracle(nftOracle.address);
  await setNFTOracleTx.wait();
  const setTokenOracleTx = await addressProvider.setTokenOracle(
    tokenOracle.address
  );
  await setTokenOracleTx.wait();
  const setFeeDistributorTx = await addressProvider.setFeeDistributor(
    feeDistributor.address
  );
  await setFeeDistributorTx.wait();
  const setNativeTokenTx = await addressProvider.setNativeToken(
    nativeToken.address
  );
  await setNativeTokenTx.wait();
  const setNativeTokenVestingTx = await addressProvider.setNativeTokenVesting(
    nativeTokenVesting.address
  );
  await setNativeTokenVestingTx.wait();
  const setLoanCenterTx = await addressProvider.setLoanCenter(
    loanCenter.address
  );
  await setLoanCenterTx.wait();
  const setGenesisNFT = await addressProvider.setGenesisNFT(genesisNFT.address);
  await setGenesisNFT.wait();
  const setVotingEscrowTx = await addressProvider.setVotingEscrow(
    votingEscrow.address
  );
  await setVotingEscrowTx.wait();
  const setSwapRouterTx = await addressProvider.setSwapRouter(
    swapRouter.address
  );
  await setSwapRouterTx.wait();
  const setTradingPoolFactoryTx = await addressProvider.setTradingPoolFactory(
    tradingPoolFactory.address
  );
  await setTradingPoolFactoryTx.wait();
  const setTradingPoolHelpersTx = await addressProvider.setTradingPoolHelpers(
    tradingPoolHelpers.address
  );
  await setTradingPoolHelpersTx.wait();
  const setGaugeControllerTx = await addressProvider.setGaugeController(
    gaugeController.address
  );
  await setGaugeControllerTx.wait();
  const setBribesTx = await addressProvider.setBribes(bribes.address);
  await setBribesTx.wait();
  const setWETHTx = await addressProvider.setWETH(weth.address);
  await setWETHTx.wait();

  // Set trusted price source
  const setTrustedPriceSourceTx = await nftOracle.setTrustedPriceSigner(
    priceSigner,
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
    wethAddress,
    "1000000000000000000" //1 testToken/ETH
  );
  await setTestTokenPriceTx.wait();

  // Add WETH parameters to interest rate contract
  const setWETHInterestRateParamsTx = await interestRate.addToken(wethAddress, {
    optimalUtilizationRate: 7000,
    baseBorrowRate: 500,
    lowSlope: 2000,
    highSlope: 20000,
  });
  await setWETHInterestRateParamsTx.wait();

  // Set price curves
  const setExponentialCurveTx = await tradingPoolFactory.setPriceCurve(
    exponentialCurve.address,
    true
  );
  await setExponentialCurveTx.wait();
  const setLinearCurveTx = await tradingPoolFactory.setPriceCurve(
    linearCurve.address,
    true
  );
  await setLinearCurveTx.wait();

  // Mint 10M tokens to the owner through the vesting contract
  const setVestingTx = await nativeTokenVesting.setVesting(
    owner.address,
    0,
    7 * 24 * 60 * 60, // 7 days
    ethers.utils.parseEther("10000000") // 10M tokens
  );
  await setVestingTx.wait();

  // Let 7 days pass
  await time.increase(7 * 24 * 60 * 60);

  // Mint 10M tokens to the owner
  const mintTx = await nativeTokenVesting.withdraw(
    ethers.utils.parseEther("10000000") // 10M tokens
  );
  await mintTx.wait();

  console.log("loaded");
};

function loadTest(isMainnetFork) {
  before(() => loadEnv(isMainnetFork));
}

function loadTestAlways(isMainnetFork) {
  beforeEach(() => loadEnv(isMainnetFork));
}

exports.loadTest = loadTest;
exports.loadTestAlways = loadTestAlways;
