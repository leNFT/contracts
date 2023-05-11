const { ethers } = require("hardhat");

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
  console.log("chainID: ", chainID.toString());
  var addresses = contractAddresses[chainID.toString()];
  const ONE_DAY = 86400;

  var devAddress;
  if (chainID == 1) {
    devAddress = process.env.MAINNET_DEV_ADDRESS;
  } else {
    devAddress = process.env.TESTNET_DEV_ADDRESS;
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

  console.log("Deployed Libraries");

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
      "25000000000000000000", // TVL Safeguard for pools
      {
        maxLiquidatorDiscount: "2000", // maxLiquidatorDiscount
        auctionerFee: "50", // defaultAuctionerFee
        liquidationFee: "200", // defaultProtocolLiquidationFee
        maxUtilizationRate: "8500", // defaultmaxUtilizationRate
      },
    ],
    { unsafeAllow: ["external-library-linking"], timeout: 0 }
  );
  addresses["LendingMarket"] = lendingMarket.address;

  // Deploy and initialize loan center provider proxy
  const LoanCenter = await ethers.getContractFactory("LoanCenter");
  const loanCenter = await upgrades.deployProxy(LoanCenter, [
    addressesProvider.address,
    {
      maxLTV: "3000", // Default Max LTV for loans - 30%
      liquidationThreshold: "6000", // Default Liquidation Threshold for loanss - 60%
    },
  ]);
  addresses["LoanCenter"] = loanCenter.address;

  console.log("Deployed LoanCenter");

  // Deploy and initialize the native token (different for mainnet and sepolia)
  const NativeToken = await ethers.getContractFactory("NativeToken");
  const nativeToken = await upgrades.deployProxy(NativeToken, [
    addressesProvider.address,
    "leNFT Token",
    "LE",
    "100000000000000000000000000", //100M Max Cap
  ]);
  addresses["NativeToken"] = nativeToken.address;

  console.log("Deployed NativeToken");

  // Deploy and initialize Genesis NFT
  const GenesisNFT = await ethers.getContractFactory("GenesisNFT");
  const genesisNFT = await upgrades.deployProxy(GenesisNFT, [
    addressesProvider.address,
    "leNFT Genesis",
    "LGEN",
    "3333", // 3333 of total supply
    "350000000000000000", // 0.35 ETH Price
    "250", // 2.5% LTV Boost for Genesis NFT
    12500000, // Native Token Mint Factor
    ONE_DAY * 180, // Max locktime (180 days in s)
    ONE_DAY * 14, // Min locktime (14 days in s)
    devAddress,
  ]);
  addresses["GenesisNFT"] = genesisNFT.address;

  console.log("Deployed GenesisNFT");

  // Deploy and initialize Voting Escrow contract
  const VotingEscrow = await ethers.getContractFactory("VotingEscrow");
  const votingEscrow = await upgrades.deployProxy(VotingEscrow, [
    addressesProvider.address,
    "Vote Escrowed LE",
    "veLE",
  ]);
  addresses["VotingEscrow"] = votingEscrow.address;

  console.log("Deployed VotingEscrow");

  // Deploy and initialize Gauge Controller
  const GaugeController = await ethers.getContractFactory("GaugeController");
  const gaugeController = await upgrades.deployProxy(GaugeController, [
    addressesProvider.address,
    "280000000000000000000000", // Initial epoch rewards (280k LE)
    6, // LP Maturation Period (in epochs)
  ]);
  addresses["GaugeController"] = gaugeController.address;

  console.log("Deployed GaugeController");

  // Deploy and initialize Fee distributor
  const FeeDistributor = await ethers.getContractFactory("FeeDistributor");
  const feeDistributor = await upgrades.deployProxy(FeeDistributor, [
    addressesProvider.address,
  ]);
  addresses["FeeDistributor"] = feeDistributor.address;

  console.log("Deployed FeeDistributor");

  // Deploy and initialize the Bribes contract
  const Bribes = await ethers.getContractFactory("Bribes");
  const bribes = await upgrades.deployProxy(Bribes, [
    addressesProvider.address,
  ]);
  addresses["Bribes"] = bribes.address;

  console.log("Deployed Bribes");

  // Deploy and initialize Trading Pool Factory
  const TradingPoolFactory = await ethers.getContractFactory(
    "TradingPoolFactory"
  );
  const tradingPoolFactory = await upgrades.deployProxy(TradingPoolFactory, [
    addressesProvider.address,
    "1000", // Default protocol fee percentage (10%)
    "25000000000000000000", // TVL Safeguard for pools
  ]);
  addresses["TradingPoolFactory"] = tradingPoolFactory.address;

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
  const liquidityPairMetadata = await LiquidityPairMetadata.deploy();
  await liquidityPairMetadata.deployed();
  addresses["LiquidityPairMetadata"] = liquidityPairMetadata.address;

  // Deploy the Interest Rate contract
  const InterestRate = await ethers.getContractFactory("InterestRate");
  const interestRate = await InterestRate.deploy();
  await interestRate.deployed();
  addresses["InterestRate"] = interestRate.address;

  // Deploy the NFT Oracle contract
  const NFTOracle = await ethers.getContractFactory("NFTOracle");
  const nftOracle = await NFTOracle.deploy(addressesProvider.address);
  await nftOracle.deployed();
  addresses["NFTOracle"] = nftOracle.address;

  // Deploy TokenOracle contract
  const TokenOracle = await ethers.getContractFactory("TokenOracle");
  const tokenOracle = await TokenOracle.deploy();
  await tokenOracle.deployed();
  addresses["TokenOracle"] = tokenOracle.address;

  // Deploy Swap Router
  const SwapRouter = await ethers.getContractFactory("SwapRouter");
  const swapRouter = await SwapRouter.deploy(addressesProvider.address);
  addresses["SwapRouter"] = swapRouter.address;

  // Deploy WETH Gateway contract
  const WETHGateway = await ethers.getContractFactory("WETHGateway");
  const wethGateway = await WETHGateway.deploy(
    addressesProvider.address,
    addresses["ETH"].address
  );
  await wethGateway.deployed();
  addresses["WETHGateway"] = wethGateway.address;

  console.log("Set WETHGateway with WETH @ " + addresses["ETH"].address);

  // Deploy price curves contracts
  const ExponentialCurve = await ethers.getContractFactory(
    "ExponentialPriceCurve"
  );
  const exponentialCurve = await ExponentialCurve.deploy();
  await exponentialCurve.deployed();
  addresses["ExponentialCurve"] = exponentialCurve.address;
  const LinearCurve = await ethers.getContractFactory("LinearPriceCurve");
  const linearCurve = await LinearCurve.deploy();
  await linearCurve.deployed();
  addresses["LinearCurve"] = linearCurve.address;

  console.log("Deployed Non-Proxies");

  // If we are not on mainnet, deploy a faucet contract
  var nativeTokenFaucet;
  if (chainID != 1) {
    const NativeTokenFaucet = await ethers.getContractFactory(
      "NativeTokenFaucet"
    );
    nativeTokenFaucet = await NativeTokenFaucet.deploy(
      addressesProvider.address
    );
    await nativeTokenFaucet.deployed();
    addresses["NativeTokenFaucet"] = nativeTokenFaucet.address;
  }

  /****************************************************************
  SAVE TO DISK
  Write contract addresses to file
  ******************************************************************/

  var fs = require("fs");
  contractAddresses[chainID.toString()] = addresses;
  fs.writeFileSync(
    "../lenft-interface-v2/contractAddresses.json",
    JSON.stringify(contractAddresses),
    function (err) {
      if (err) throw err;
      console.log("File written to interface folder");
    }
  );
  fs.writeFileSync(
    "../lenft-interface/contractAddresses.json",
    JSON.stringify(contractAddresses),
    function (err) {
      if (err) throw err;
      console.log("File written to interface folder");
    }
  );
  fs.writeFileSync(
    "../lenft-api/contractAddresses.json",
    JSON.stringify(contractAddresses),
    function (err) {
      if (err) throw err;
      console.log("File written to API folder");
    }
  );
  fs.writeFileSync(
    "../trade-router/contractAddresses.json",
    JSON.stringify(contractAddresses),
    function (err) {
      if (err) throw err;
      console.log("File written to API folder");
    }
  );
  fs.writeFileSync(
    "../lenft/contractAddresses.json",
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

  //Set every address in the address provider
  const setLendingMarketTx = await addressesProvider.setLendingMarket(
    lendingMarket.address
  );
  await setLendingMarketTx.wait();
  const setTradingPoolFactoryTx = await addressesProvider.setTradingPoolFactory(
    tradingPoolFactory.address
  );
  await setTradingPoolFactoryTx.wait();
  const setLiquidityPairMetadataTx =
    await addressesProvider.setLiquidityPairMetadata(
      liquidityPairMetadata.address
    );
  await setLiquidityPairMetadataTx.wait();
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
  const setSwapRouterTx = await addressesProvider.setSwapRouter(
    swapRouter.address
  );
  await setSwapRouterTx.wait();

  // Set bribes address
  const setBribesTx = await addressesProvider.setBribes(bribes.address);
  await setBribesTx.wait();

  // Set WETH address
  const setWETHTx = await addressesProvider.setWETH(addresses["ETH"].address);
  await setWETHTx.wait();

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

  // If we are not on mainnet mint LE and fund the faucet
  if (chainID != 1) {
    const mintTx = await nativeToken.mint(
      nativeTokenFaucet.address,
      ethers.utils.parseEther("100000")
    );
    await mintTx.wait();
  }
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
