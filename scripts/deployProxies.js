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
  [owner] = await ethers.getSigners();

  /****************************************************************
  DEPLOY LIBRARIES
  They will then be linked to the contracts that use them
  ******************************************************************/

  // Deploy borrow logic lib
  BorrowLogicLib = await ethers.getContractFactory("BorrowLogic");
  borrowLogicLib = await BorrowLogicLib.deploy();
  addresses["BorrowLogicLib"] = borrowLogicLib.address;

  // Deploy liquidation logic lib
  LiquidationLogicLib = await ethers.getContractFactory("LiquidationLogic");
  liquidationLogicLib = await LiquidationLogicLib.deploy();
  addresses["LiquidationLogicLib"] = liquidationLogicLib.address;

  console.log("Deployed Libraries");

  /****************************************************************
  DEPLOY PROXIES
  They will serve as an entry point for the upgraded contracts
  ******************************************************************/

  // Deploy and initialize addresses provider proxy
  const AddressProvider = await ethers.getContractFactory("AddressProvider");
  const addressProvider = await upgrades.deployProxy(AddressProvider);
  addresses["AddressProvider"] = addressProvider.address;

  // Deploy and initialize market proxy
  const LendingMarket = await ethers.getContractFactory("LendingMarket", {
    libraries: {
      BorrowLogic: borrowLogicLib.address,
      LiquidationLogic: liquidationLogicLib.address,
    },
  });
  const lendingMarket = await upgrades.deployProxy(
    LendingMarket,
    [
      addressProvider.address,
      "25000000000000000000", // TVL Safeguard for pools
      {
        maxLiquidatorDiscount: "2000", // maxLiquidatorDiscount
        auctioneerFeeRate: "100", // defaultAuctioneerFee
        liquidationFeeRate: "200", // defaultProtocolLiquidationFee
        maxUtilizationRate: "8500", // defaultmaxUtilizationRate
      },
    ],
    { unsafeAllow: ["external-library-linking"], timeout: 0 }
  );
  addresses["LendingMarket"] = lendingMarket.address;

  // Deploy and initialize loan center provider proxy
  const LoanCenter = await ethers.getContractFactory("LoanCenter");
  const loanCenter = await upgrades.deployProxy(LoanCenter, [
    addressProvider.address,
    "3000", // Default Max LTV for loans - 30%
    "6000", // Default Liquidation Threshold for loanss - 60%
  ]);
  addresses["LoanCenter"] = loanCenter.address;

  console.log("Deployed LoanCenter");

  // Deploy and initialize the native token (different for mainnet and sepolia)
  const NativeToken = await ethers.getContractFactory("NativeToken");
  const nativeToken = await upgrades.deployProxy(NativeToken, [
    addressProvider.address,
  ]);
  addresses["NativeToken"] = nativeToken.address;

  console.log("Deployed NativeToken");

  // Deploy and initialize Genesis NFT
  const GenesisNFT = await ethers.getContractFactory("GenesisNFT");
  const genesisNFT = await upgrades.deployProxy(GenesisNFT, [
    addressProvider.address,
    "250", // 2.5% LTV Boost for Genesis NFT
    owner.address, // TO:DO Set to dev address for Mainnet
  ]);
  addresses["GenesisNFT"] = genesisNFT.address;

  console.log("Deployed GenesisNFT");

  // Deploy and initialize Voting Escrow contract
  const VotingEscrow = await ethers.getContractFactory("VotingEscrow");
  const votingEscrow = await upgrades.deployProxy(VotingEscrow, [
    addressProvider.address,
  ]);
  addresses["VotingEscrow"] = votingEscrow.address;

  console.log("Deployed VotingEscrow");

  // Deploy and initialize Gauge Controller
  const GaugeController = await ethers.getContractFactory("GaugeController");
  const gaugeController = await upgrades.deployProxy(GaugeController, [
    addressProvider.address,
    6 * 7 * 24 * 3600, // Default LP Maturation Period in seconds (set to 6 weeks)
  ]);
  addresses["GaugeController"] = gaugeController.address;

  console.log("Deployed GaugeController");

  // Deploy and initialize Fee distributor
  const FeeDistributor = await ethers.getContractFactory("FeeDistributor");
  const feeDistributor = await upgrades.deployProxy(FeeDistributor, [
    addressProvider.address,
  ]);
  addresses["FeeDistributor"] = feeDistributor.address;

  console.log("Deployed FeeDistributor");

  // Deploy and initialize the Bribes contract
  const Bribes = await ethers.getContractFactory("Bribes");
  const bribes = await upgrades.deployProxy(Bribes, [addressProvider.address]);
  addresses["Bribes"] = bribes.address;

  console.log("Deployed Bribes");

  // Deploy and initialize Trading Pool Factory
  const TradingPoolFactory = await ethers.getContractFactory(
    "TradingPoolFactory"
  );
  const tradingPoolFactory = await upgrades.deployProxy(TradingPoolFactory, [
    addressProvider.address,
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

  // Deploy the trading pool helper contract
  const TradingPoolHelpers = await ethers.getContractFactory(
    "TradingPoolHelpers"
  );
  const tradingPoolHelpers = await TradingPoolHelpers.deploy(
    addressProvider.address
  );
  await tradingPoolHelpers.deployed();
  addresses["TradingPoolHelpers"] = tradingPoolHelpers.address;

  // Deploy the Interest Rate contract
  const InterestRate = await ethers.getContractFactory("InterestRate");
  const interestRate = await InterestRate.deploy();
  await interestRate.deployed();
  addresses["InterestRate"] = interestRate.address;

  // Deploy the NFT Oracle contract
  const NFTOracle = await ethers.getContractFactory("NFTOracle");
  const nftOracle = await NFTOracle.deploy();
  await nftOracle.deployed();
  addresses["NFTOracle"] = nftOracle.address;

  // Deploy TokenOracle contract
  const TokenOracle = await ethers.getContractFactory("TokenOracle");
  const tokenOracle = await TokenOracle.deploy();
  await tokenOracle.deployed();
  addresses["TokenOracle"] = tokenOracle.address;

  // Deploy Swap Router
  const SwapRouter = await ethers.getContractFactory("SwapRouter");
  const swapRouter = await SwapRouter.deploy(addressProvider.address);
  addresses["SwapRouter"] = swapRouter.address;

  // Deploy WETH Gateway contract
  const WETHGateway = await ethers.getContractFactory("WETHGateway");
  const wethGateway = await WETHGateway.deploy(
    addressProvider.address,
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

  // Deploy the vesting contract
  const NativeTokenVesting = await ethers.getContractFactory(
    "NativeTokenVesting"
  );
  const nativeTokenVesting = await NativeTokenVesting.deploy(
    addressProvider.address
  );
  await nativeTokenVesting.deployed();
  addresses["NativeTokenVesting"] = nativeTokenVesting.address;

  console.log("Deployed Non-Proxies");

  // If we are not on mainnet, deploy a faucet contract
  var nativeTokenFaucet;
  if (chainID != 1) {
    const NativeTokenFaucet = await ethers.getContractFactory(
      "NativeTokenFaucet"
    );
    nativeTokenFaucet = await NativeTokenFaucet.deploy(addressProvider.address);
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
  const setLendingMarketTx = await addressProvider.setLendingMarket(
    lendingMarket.address
  );
  await setLendingMarketTx.wait();
  const setTradingPoolFactoryTx = await addressProvider.setTradingPoolFactory(
    tradingPoolFactory.address
  );
  await setTradingPoolFactoryTx.wait();
  const setLiquidityPairMetadataTx =
    await addressProvider.setLiquidityPairMetadata(
      liquidityPairMetadata.address
    );
  await setLiquidityPairMetadataTx.wait();
  const setTradingPoolHelpersTx = await addressProvider.setTradingPoolHelpers(
    tradingPoolHelpers.address
  );
  await setTradingPoolHelpersTx.wait();
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
  const setLoanCenterTx = await addressProvider.setLoanCenter(
    loanCenter.address
  );
  await setLoanCenterTx.wait();

  const setNativeTokenTx = await addressProvider.setNativeToken(
    nativeToken.address
  );
  await setNativeTokenTx.wait();
  const setNativeTokenVestingTx = await addressProvider.setNativeTokenVesting(
    nativeTokenVesting.address
  );
  await setNativeTokenVestingTx.wait();
  const setGenesisNFT = await addressProvider.setGenesisNFT(genesisNFT.address);
  await setGenesisNFT.wait();
  const setFeeDistributorTx = await addressProvider.setFeeDistributor(
    feeDistributor.address
  );
  await setFeeDistributorTx.wait();
  const setGaugeControllerTx = await addressProvider.setGaugeController(
    gaugeController.address
  );
  await setGaugeControllerTx.wait();
  const setVotingEscrowTx = await addressProvider.setVotingEscrow(
    votingEscrow.address
  );
  await setVotingEscrowTx.wait();
  const setSwapRouterTx = await addressProvider.setSwapRouter(
    swapRouter.address
  );
  await setSwapRouterTx.wait();

  // Set bribes address
  const setBribesTx = await addressProvider.setBribes(bribes.address);
  await setBribesTx.wait();

  // Set WETH address
  const setWETHTx = await addressProvider.setWETH(addresses["ETH"].address);
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
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
