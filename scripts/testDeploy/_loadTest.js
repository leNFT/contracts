const { ethers } = require("hardhat");

let loadEnv = async function () {
  console.log("Setting up enviroment...");

  [owner, addr1, addr2] = await ethers.getSigners();

  //Deploy libraries
  ValidationLogicLib = await ethers.getContractFactory("ValidationLogic");
  validationLogicLib = await ValidationLogicLib.deploy();
  console.log("Validation Logic Lib Address:", validationLogicLib.address);
  SupplyLogicLib = await ethers.getContractFactory("SupplyLogic", {
    libraries: {
      ValidationLogic: validationLogicLib.address,
    },
  });
  supplyLogicLib = await SupplyLogicLib.deploy();
  console.log("Supply Logic Lib Address:", supplyLogicLib.address);
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

  // Deploy every needed contract
  const AddressesProvider = await ethers.getContractFactory(
    "AddressesProvider"
  );
  const addressesProvider = await AddressesProvider.deploy();
  await addressesProvider.deployed();
  console.log("Addresses Provider Address:", addressesProvider.address);
  const WETH = await ethers.getContractFactory("WETH");
  weth = await WETH.deploy();
  await weth.deployed();
  console.log("WETH Address:", weth.address);
  const TestNFT = await ethers.getContractFactory("TestNFT");
  testNFT = await TestNFT.deploy("TEST NFT", "TNFT");
  await testNFT.deployed();
  console.log("Test NFT Address:", testNFT.address);
  testNFT2 = await TestNFT.deploy("TEST NFT2", "TNFT2");
  await testNFT2.deployed();
  console.log("Test NFT2 Address:", testNFT2.address);
  const Market = await ethers.getContractFactory("Market", {
    libraries: {
      BorrowLogic: borrowLogicLib.address,
      LiquidationLogic: liquidationLogicLib.address,
      SupplyLogic: supplyLogicLib.address,
    },
  });
  market = await Market.deploy();
  await market.deployed();
  console.log("Market Address:", market.address);
  const LoanCenter = await ethers.getContractFactory("LoanCenter");
  loanCenter = await LoanCenter.deploy();
  await loanCenter.deployed();
  console.log("Loan Center Address:", loanCenter.address);
  const WETHReserve = await ethers.getContractFactory("Reserve", {
    libraries: {
      SupplyLogic: supplyLogicLib.address,
    },
  });
  wethReserve = await WETHReserve.deploy();
  await wethReserve.deployed();
  const InterestRate = await ethers.getContractFactory("InterestRate");
  interestRate = await InterestRate.deploy(8000, 1000, 2500, 10000);
  await interestRate.deployed();
  console.log("Interest Rate Address:", interestRate.address);
  const NFTOracle = await ethers.getContractFactory("NFTOracle");
  nftOracle = await NFTOracle.deploy(addressesProvider.address);
  await nftOracle.deployed();
  console.log("NFT Oracle Address:", nftOracle.address);
  const TokenOracle = await ethers.getContractFactory("TokenOracle");
  tokenOracle = await TokenOracle.deploy();
  await tokenOracle.deployed();
  console.log("Token Oracle Address:", tokenOracle.address);

  // Deploy Native Token Vault
  const NativeTokenVault = await ethers.getContractFactory("NativeTokenVault", {
    libraries: {
      ValidationLogic: validationLogicLib.address,
    },
  });
  nativeTokenVault = await NativeTokenVault.deploy();
  await nativeTokenVault.deployed();
  console.log("Native Token Vault Address:", nativeTokenVault.address);

  // Deploy Native Token
  const NativeToken = await ethers.getContractFactory("NativeToken");
  nativeToken = await NativeToken.deploy();
  await nativeToken.deployed();
  console.log("Native Token Address:", nativeToken.address);

  // Deploy Debt Token
  const DebtToken = await ethers.getContractFactory("DebtToken");
  debtToken = await DebtToken.deploy();
  await debtToken.deployed();
  console.log("Debt Token Address:", debtToken.address);

  // Deploy Genesis NFT
  const GenesisNFT = await ethers.getContractFactory("GenesisNFT");
  genesisNFT = await GenesisNFT.deploy();
  await genesisNFT.deployed();
  console.log("Genesis NFT Address:", genesisNFT.address);

  // Initialize address provider and add every contract address
  const initAddressesProviderTx = await addressesProvider.initialize();
  await initAddressesProviderTx.wait();
  const setMarketAddressTx = await addressesProvider.setMarketAddress(
    market.address
  );
  await setMarketAddressTx.wait();
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
  const setNativeTokenVaultTx = await addressesProvider.setNativeTokenVault(
    nativeTokenVault.address
  );
  await setNativeTokenVaultTx.wait();
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
  feeTreasuryAddress = "0xa5C6eD5d801417c50f775099BA59C306d4034D4D";
  const setFeeTreasuryTx = await addressesProvider.setFeeTreasury(
    feeTreasuryAddress
  );
  await setFeeTreasuryTx.wait();
  const setWETHTx = await addressesProvider.setWETH(weth.address);
  await setWETHTx.wait();

  // Initialize market
  const initMarketTx = await market.initialize(addressesProvider.address);
  await initMarketTx.wait();

  //Initialize LoanCenter
  const initLoanCenterTx = await loanCenter.initialize(
    addressesProvider.address
  );
  await initLoanCenterTx.wait();

  // Initialize Reserve
  const initReserveTx = await wethReserve.initialize(
    addressesProvider.address,
    weth.address,
    "RESERVETOKEN",
    "RTTOKEN",
    9000, //max utilization rate (90%)
    1200, // Liquidation penalty (12%)
    200, // protocol liquidation fee (2%)
    "1001000000000000000000" //Underlying safeguard (can deposit up to 1001 ETH)
  );
  await initReserveTx.wait();

  //Init debt token
  const initDebtTokenTx = await debtToken.initialize(
    addressesProvider.address,
    "DEBT TOKEN",
    "DEBT"
  );
  await initDebtTokenTx.wait();

  //Init native token
  const initNativeTokenTx = await nativeToken.initialize(
    addressesProvider.address,
    "leNFT Token",
    "LE",
    "100000000000000000000000000", //100M Max Cap
    owner.address,
    "15000000000000000000000000", // 15M Dev Tokens
    "63113851", // 2-year dev vesting
    "604800", // 7-day period between vault rewards
    "312", // Limit number of periods
    "283000000000000000000000" // Rewards Factor
  );
  await initNativeTokenTx.wait();

  //Init native token vault
  const initNativeTokenVaultTx = await nativeTokenVault.initialize(
    addressesProvider.address,
    "veleNFT Token",
    "veLE",
    "25000000000000000000000", // 25000 leNFT Reward Limit
    "10000000000000000", // 0.01 Liquidation Reward Factor
    9000, // Liquidation Reward Price Threshold (90%)
    12000, // Liquidation Reward Price Limit (120%)
    1500, //15% Boost Limit
    "15000000000000000000" // 15 Boost Factor
  );
  await initNativeTokenVaultTx.wait();

  //Init Genesis NFT
  const initGenesisNFTTx = await genesisNFT.initialize(
    addressesProvider.address,
    "leNFT Genesis",
    "LGEN",
    "9999",
    "300000000000000000",
    "250",
    3000000, // Native Token Mint Factor
    10368000, // Max locktime (120 days in s)
    1209600, // Min locktime (14 days in s)
    owner.address
  );
  await initGenesisNFTTx.wait();

  // Add reserve to market
  const addReserveTx = await market.addReserve(
    weth.address,
    wethReserve.address
  );
  await addReserveTx.wait();

  //Add test NFTs to oracle
  const addNftToOracleTx = await nftOracle.addSupportedCollection(
    testNFT.address,
    2000 //max collaterization (20%)
  );
  await addNftToOracleTx.wait();
  const addNft2ToOracleTx = await nftOracle.addSupportedCollection(
    testNFT2.address,
    4000 //max collaterization (40%)
  );
  await addNft2ToOracleTx.wait();

  // Set trusted price source
  const setTrustedPriceSourceTx = await nftOracle.addTrustedPriceSource(
    "0xfEa2AF8BB65c34ee64A005057b4C749310321Fa0"
  );
  await setTrustedPriceSourceTx.wait();

  //Approve test nfts to be used by market
  const approveNFTCollectionTx = await loanCenter.approveNFTCollection(
    testNFT.address
  );
  await approveNFTCollectionTx.wait();
  const approveNFT2CollectionTx = await loanCenter.approveNFTCollection(
    testNFT2.address
  );
  await approveNFT2CollectionTx.wait();

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
};

function loadTest() {
  before(loadEnv);
}

exports.loadTest = loadTest;
exports.loadEnv = loadEnv;
