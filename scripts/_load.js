require("@nomiclabs/hardhat-ethers");

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
    "MarketAddressesProvider"
  );
  const addressesProvider = await AddressesProvider.deploy();
  await addressesProvider.deployed();
  console.log("Addresses Provider Address:", addressesProvider.address);
  const TestToken = await ethers.getContractFactory("TestToken");
  testToken = await TestToken.deploy("Wrapped ETH", "wETH");
  await testToken.deployed();
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
  const TestReserve = await ethers.getContractFactory("Reserve", {
    libraries: {
      SupplyLogic: supplyLogicLib.address,
    },
  });
  testReserve = await TestReserve.deploy();
  await testReserve.deployed();
  const InterestRate = await ethers.getContractFactory("InterestRate");
  interestRate = await InterestRate.deploy(8000, 1000, 2500, 10000);
  await interestRate.deployed();
  console.log("Interest Rate Address:", interestRate.address);
  const NFTOracle = await ethers.getContractFactory("NFTOracle");
  nftOracle = await NFTOracle.deploy(addressesProvider.address, 2000, 1); //Max Price deviation (20%) and min update time
  await nftOracle.deployed();
  console.log("NFT Oracle Address:", nftOracle.address);

  // Deploy Token Oracle
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
  const setLoanCenterTx = await addressesProvider.setLoanCenter(
    loanCenter.address
  );
  await setLoanCenterTx.wait();
  feeTreasuryAddress = "0xa5C6eD5d801417c50f775099BA59C306d4034D4D";
  const setFeeTreasuryTx = await addressesProvider.setFeeTreasury(
    feeTreasuryAddress
  );
  await setFeeTreasuryTx.wait();

  // Initialize market
  const initMarketTx = await market.initialize(addressesProvider.address);
  await initMarketTx.wait();

  //Initialize LoanCenter
  const initLoanCenterTx = await loanCenter.initialize(
    addressesProvider.address
  );
  await initLoanCenterTx.wait();

  // Initialize Reserve
  const initReserveTx = await testReserve.initialize(
    addressesProvider.address,
    testToken.address,
    "RESERVETESTTOKEN",
    "RTTOKEN",
    9000, //max utilization rate (90%)
    2000, // Liquidation penalty (20%)
    200 // protocol fee (2%)
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
    "100000000000000000000000000" //100M Max Cap
  );
  await initNativeTokenTx.wait();

  //Init native token vault
  const initNativeTokenVaultTx = await nativeTokenVault.initialize(
    addressesProvider.address,
    nativeToken.address,
    "veleNFT Token",
    "veLE"
  );
  await initNativeTokenVaultTx.wait();

  // Add reserve to market
  const addReserveTx = await market.addReserve(
    testToken.address,
    testReserve.address
  );
  await addReserveTx.wait();

  //Add test NFTs to oracle
  const addNftToOracleTx = await nftOracle.addSupportedCollection(
    testNFT.address,
    "500000000000000000000", //500 tokens floor price
    2000 //max collaterization (20%)
  );
  await addNftToOracleTx.wait();
  const addNft2ToOracleTx = await nftOracle.addSupportedCollection(
    testNFT2.address,
    "500000000000000000", //0.5 tokens floor price
    4000 //max collaterization (20%)
  );
  await addNft2ToOracleTx.wait();

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
  const setNativeTokenPriceTx = await tokenOracle.setTokenPrice(
    nativeToken.address,
    "1000000000000000000" //1 eth token price
  );
  await setNativeTokenPriceTx.wait();
};

function loadTest() {
  before(loadEnv);
}

exports.loadTest = loadTest;
exports.loadEnv = loadEnv;
