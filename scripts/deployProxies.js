const { getContractFactory } = require("@nomiclabs/hardhat-ethers/types");
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
  [owner] = await ethers.getSigners();
  const fundedAddress = "0xA26B0242f21c53144fA7B23e0D2f73D6C2684472";

  console.log("Deploying contracts with the account:", owner.address);

  /****************************************************************
  DEPLOY LIBRARIES
  They will then be linked to the contracts that use them
  ******************************************************************/

  // Deploy borrow logic lib
  BorrowLogicLib = await ethers.getContractFactory("BorrowLogic");
  borrowLogicLib = await BorrowLogicLib.deploy();
  addresses["BorrowLogicLib"] = borrowLogicLib.address;

  console.log("Deployed BorrowLogicLib", borrowLogicLib.address);

  // Deploy liquidation logic lib
  LiquidationLogicLib = await ethers.getContractFactory("LiquidationLogic");
  liquidationLogicLib = await LiquidationLogicLib.deploy();
  addresses["LiquidationLogicLib"] = liquidationLogicLib.address;

  console.log("Deployed LiquidationLogicLib", liquidationLogicLib.address);

  console.log("Deployed Libraries");

  /****************************************************************
  DEPLOY PROXIES
  They will serve as an entry point for the upgraded contracts
  ******************************************************************/

  // Deploy and initialize addresses provider proxy
  const AddressProvider = await ethers.getContractFactory("AddressProvider");
  const addressProvider = await upgrades.deployProxy(AddressProvider);
  addresses["AddressProvider"] = addressProvider.address;

  console.log("Deployed AddressProvider", addressProvider.address);

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
      "25000000000000000000", // TVL Safeguard for pools
      {
        maxLiquidatorDiscount: "2000", // maxLiquidatorDiscount
        auctioneerFeeRate: "100", // defaultAuctioneerFee
        liquidationFeeRate: "200", // defaultProtocolLiquidationFee
        maxUtilizationRate: "8500", // defaultmaxUtilizationRate
      },
    ],
    {
      unsafeAllow: ["external-library-linking", "state-variable-immutable"],
      timeout: 0,
      constructorArgs: [addressProvider.address],
    }
  );
  addresses["LendingMarket"] = lendingMarket.address;
  console.log("Deployed LendingMarket", lendingMarket.address);

  // Deploy and initialize loan center provider proxy
  const LoanCenter = await ethers.getContractFactory("LoanCenter");
  const loanCenter = await upgrades.deployProxy(
    LoanCenter,
    [
      "3000", // Default Max LTV for loans - 30%
      "6000", // Default Liquidation Threshold for loanss - 60%
    ],
    {
      unsafeAllow: ["state-variable-immutable"],
      constructorArgs: [addressProvider.address],
    }
  );
  addresses["LoanCenter"] = loanCenter.address;

  console.log("Deployed LoanCenter", loanCenter.address);

  //Deploy and initialize the native token (different for mainnet and sepolia)
  const NativeToken = await ethers.getContractFactory("NativeToken");
  const nativeToken = await upgrades.deployProxy(NativeToken, [], {
    unsafeAllow: ["state-variable-immutable"],
    constructorArgs: [addressProvider.address],
  });
  addresses["NativeToken"] = nativeToken.address;

  console.log("Deployed NativeToken", nativeToken.address);

  // Deploy and initialize Genesis NFT
  const GenesisNFT = await ethers.getContractFactory("GenesisNFT");
  const genesisNFT = await upgrades.deployProxy(
    GenesisNFT,
    [
      "250", // 2.5% LTV Boost for Genesis NFT
      fundedAddress,
    ],
    {
      unsafeAllow: ["state-variable-immutable"],
      constructorArgs: [addressProvider.address],
    }
  );
  addresses["GenesisNFT"] = genesisNFT.address;

  console.log("Deployed GenesisNFT", genesisNFT.address);

  // Deploy and initialize Voting Escrow contract
  const VotingEscrow = await ethers.getContractFactory("VotingEscrow");
  const votingEscrow = await upgrades.deployProxy(VotingEscrow, [], {
    unsafeAllow: ["state-variable-immutable"],
    constructorArgs: [addressProvider.address],
  });
  addresses["VotingEscrow"] = votingEscrow.address;

  console.log("Deployed VotingEscrow", votingEscrow.address);

  // Deploy and initialize Gauge Controller
  const GaugeController = await ethers.getContractFactory("GaugeController");
  const gaugeController = await upgrades.deployProxy(
    GaugeController,
    [
      6 * 7 * 24 * 3600, // Default LP Maturation Period in seconds (set to 6 weeks)
    ],
    {
      unsafeAllow: ["state-variable-immutable"],
      constructorArgs: [addressProvider.address],
    }
  );
  addresses["GaugeController"] = gaugeController.address;

  console.log("Deployed GaugeController", gaugeController.address);

  // Deploy and initialize Fee distributor
  const FeeDistributor = await ethers.getContractFactory("FeeDistributor");
  const feeDistributor = await upgrades.deployProxy(FeeDistributor, [], {
    unsafeAllow: ["state-variable-immutable"],
    constructorArgs: [addressProvider.address],
  });
  addresses["FeeDistributor"] = feeDistributor.address;

  console.log("Deployed FeeDistributor", feeDistributor.address);

  // Deploy and initialize the Bribes contract
  const Bribes = await ethers.getContractFactory("Bribes");
  const bribes = await upgrades.deployProxy(Bribes, [], {
    unsafeAllow: ["state-variable-immutable"],
    constructorArgs: [addressProvider.address],
  });
  addresses["Bribes"] = bribes.address;

  console.log("Deployed Bribes", bribes.address);

  // Deploy and initialize Trading Pool Factory
  const TradingPoolFactory = await ethers.getContractFactory(
    "TradingPoolFactory"
  );
  const tradingPoolFactory = await upgrades.deployProxy(
    TradingPoolFactory,
    [
      "1000", // Default protocol fee percentage (10%)
      "25000000000000000000", // TVL Safeguard for pools
    ],
    {
      unsafeAllow: ["state-variable-immutable"],
      constructorArgs: [addressProvider.address],
    }
  );
  addresses["TradingPoolFactory"] = tradingPoolFactory.address;

  console.log("Deployed TradingPoolFactory", tradingPoolFactory.address);

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

  console.log("Deployed LiquidityPairMetadata", liquidityPairMetadata.address);

  // Deploy the trading pool helper contract
  const TradingPoolHelpers = await ethers.getContractFactory(
    "TradingPoolHelpers"
  );
  const tradingPoolHelpers = await TradingPoolHelpers.deploy(
    "0x4Df583E7D80336cb9EE91c381A939aEE58404567"
  );
  await tradingPoolHelpers.deployed();
  addresses["TradingPoolHelpers"] = tradingPoolHelpers.address;

  console.log("Deployed TradingPoolHelpers", tradingPoolHelpers.address);

  // Deploy the Interest Rate contract
  const InterestRate = await ethers.getContractFactory("InterestRate");
  const interestRate = await InterestRate.deploy();
  await interestRate.deployed();
  addresses["InterestRate"] = interestRate.address;

  console.log("Deployed InterestRate", interestRate.address);

  // Deploy the NFT Oracle contract
  const NFTOracle = await ethers.getContractFactory("NFTOracle");
  const nftOracle = await NFTOracle.deploy();
  await nftOracle.deployed();
  addresses["NFTOracle"] = nftOracle.address;

  console.log("Deployed NFTOracle", nftOracle.address);

  // Deploy TokenOracle contract
  const TokenOracle = await ethers.getContractFactory("TokenOracle");
  const tokenOracle = await TokenOracle.deploy();
  await tokenOracle.deployed();
  addresses["TokenOracle"] = tokenOracle.address;

  console.log("Deployed TokenOracle", tokenOracle.address);

  // Deploy Swap Router
  const SwapRouter = await ethers.getContractFactory("SwapRouter");
  const swapRouter = await SwapRouter.deploy(addressProvider.address);
  addresses["SwapRouter"] = swapRouter.address;

  console.log("Deployed SwapRouter", swapRouter.address);

  // Deploy WETH Gateway contract
  const WETHGateway = await ethers.getContractFactory("WETHGateway");
  const wethGateway = await WETHGateway.deploy(
    addressProvider.address,
    addresses["ETH"].address
  );
  await wethGateway.deployed();
  addresses["WETHGateway"] = wethGateway.address;

  console.log("Deployed WETHGateway", wethGateway.address);
  console.log("Set WETHGateway with WETH @", addresses["ETH"].address);

  // Deploy price curves contracts
  const ExponentialCurve = await ethers.getContractFactory(
    "ExponentialPriceCurve"
  );
  const exponentialCurve = await ExponentialCurve.deploy();
  await exponentialCurve.deployed();
  console.log("Deployed ExponentialCurve", exponentialCurve.address);
  addresses["ExponentialCurve"] = exponentialCurve.address;
  const LinearCurve = await ethers.getContractFactory("LinearPriceCurve");
  const linearCurve = await LinearCurve.deploy();
  await linearCurve.deployed();
  console.log("Deployed LinearCurve", linearCurve.address);
  addresses["LinearCurve"] = linearCurve.address;

  // Deploy the vesting contract
  const NativeTokenVesting = await ethers.getContractFactory(
    "NativeTokenVesting"
  );
  const nativeTokenVesting = await NativeTokenVesting.deploy(
    "0x4Df583E7D80336cb9EE91c381A939aEE58404567"
  );
  await nativeTokenVesting.deployed();
  console.log("Deployed NativeTokenVesting", nativeTokenVesting.address);
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
    "../lenft-contracts/contractAddresses.json",
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
    addresses["LendingMarket"]
  );
  await setLendingMarketTx.wait();
  const setTradingPoolFactoryTx = await addressProvider.setTradingPoolFactory(
    addresses["TradingPoolFactory"]
  );
  await setTradingPoolFactoryTx.wait();
  const setLiquidityPairMetadataTx =
    await addressProvider.setLiquidityPairMetadata(
      addresses["LiquidityPairMetadata"]
    );
  await setLiquidityPairMetadataTx.wait();
  const setTradingPoolHelpersTx = await addressProvider.setTradingPoolHelpers(
    addresses["TradingPoolHelpers"]
  );
  await setTradingPoolHelpersTx.wait();
  const setInterestRateTx = await addressProvider.setInterestRate(
    addresses["InterestRate"]
  );
  await setInterestRateTx.wait();
  const setNFTOracleTx = await addressProvider.setNFTOracle(
    addresses["NFTOracle"]
  );
  await setNFTOracleTx.wait();
  const setTokenOracleTx = await addressProvider.setTokenOracle(
    addresses["TokenOracle"]
  );
  await setTokenOracleTx.wait();
  const setLoanCenterTx = await addressProvider.setLoanCenter(
    addresses["LoanCenter"]
  );
  await setLoanCenterTx.wait();

  const setNativeTokenTx = await addressProvider.setNativeToken(
    addresses["NativeToken"]
  );
  await setNativeTokenTx.wait();
  const setNativeTokenVestingTx = await addressProvider.setNativeTokenVesting(
    addresses["NativeTokenVesting"]
  );
  await setNativeTokenVestingTx.wait();
  const setGenesisNFT = await addressProvider.setGenesisNFT(
    addresses["GenesisNFT"]
  );
  await setGenesisNFT.wait();
  const setFeeDistributorTx = await addressProvider.setFeeDistributor(
    addresses["FeeDistributor"]
  );
  await setFeeDistributorTx.wait();
  const setGaugeControllerTx = await addressProvider.setGaugeController(
    addresses["GaugeController"]
  );
  await setGaugeControllerTx.wait();
  const setVotingEscrowTx = await addressProvider.setVotingEscrow(
    addresses["VotingEscrow"]
  );
  await setVotingEscrowTx.wait();
  const setSwapRouterTx = await addressProvider.setSwapRouter(
    addresses["SwapRouter"]
  );
  await setSwapRouterTx.wait();

  // Set bribes address
  const setBribesTx = await addressProvider.setBribes(addresses["Bribes"]);
  await setBribesTx.wait();

  // Set WETH address
  const setWETHTx = await addressProvider.setWETH(addresses["ETH"].address);
  await setWETHTx.wait();

  // Set price curves
  const setExponentialCurveTx = await tradingPoolFactory.setPriceCurve(
    addresses["ExponentialCurve"],
    true
  );
  await setExponentialCurveTx.wait();
  const setLinearCurveTx = await tradingPoolFactory.setPriceCurve(
    addresses["LinearCurve"],
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
