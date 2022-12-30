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
  const LendingMarket = await ethers.getContractFactory("LendingMarket", {
    libraries: {
      BorrowLogic: borrowLogicLib.address,
      LiquidationLogic: liquidationLogicLib.address,
      ValidationLogic: validationLogicLib.address,
    },
  });
  lendingMarket = await LendingMarket.deploy();
  await lendingMarket.deployed();
  console.log("Lending Market Address:", lendingMarket.address);
  const LoanCenter = await ethers.getContractFactory("LoanCenter");
  loanCenter = await LoanCenter.deploy();
  await loanCenter.deployed();
  console.log("Loan Center Address:", loanCenter.address);
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
  const WETHGateway = await ethers.getContractFactory("WETHGateway");
  wethGateway = await WETHGateway.deploy(addressesProvider.address);
  await wethGateway.deployed();
  console.log("WETHGateway Address:", wethGateway.address);

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

  // Deploy voting escrow
  const VotingEscrow = await ethers.getContractFactory("VotingEscrow");
  votingEscrow = await VotingEscrow.deploy();
  await votingEscrow.deployed();
  console.log("Voting Escrow Address:", votingEscrow.address);

  // Initialize address provider and add every contract address
  const initAddressesProviderTx = await addressesProvider.initialize();
  await initAddressesProviderTx.wait();
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
  const setWETHTx = await addressesProvider.setWETH(weth.address);
  await setWETHTx.wait();

  // Initialize lending market
  const initLendingMarketTx = await lendingMarket.initialize(
    addressesProvider.address,
    {
      liquidationPenalty: "1800", // defaultLiquidationPenalty
      liquidationFee: "200", // defaultProtocolLiquidationFee
      maximumUtilizationRate: "8500", // defaultMaximumUtilizationRate
      tvlSafeguard: "25000000000000000000", // defaultTVLSafeguard
    }
  );
  await initLendingMarketTx.wait();

  //Initialize LoanCenter
  const initLoanCenterTx = await loanCenter.initialize(
    addressesProvider.address,
    "4000" // DefaultMaxCollaterization 40%
  );
  await initLoanCenterTx.wait();

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
    ONE_DAY * 365 * 2, // 2-year dev vesting
    "20000000000000000000"
  );
  await initNativeTokenTx.wait();

  // Init voting escrow
  const initVotingEscrowTx = await votingEscrow.initialize(
    addressesProvider.address
  );
  await initVotingEscrowTx.wait();

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
