const { ethers } = require("hardhat");

let loadEnv = async function () {
  console.log("Setting up enviroment...");

  const signers = await ethers.getSigners();
  owner = signers[0];

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
  const TestToken = await ethers.getContractFactory("TestToken");
  testToken = await TestToken.deploy("Wrapped ETH", "wETH");
  await testToken.deployed();
  const TestNFT = await ethers.getContractFactory("TestNFT");
  testNFT = await TestNFT.deploy("TEST NFT", "TNFT");
  await testNFT.deployed();
  console.log("Test NFT Address:", testNFT.address);
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
  nftOracle = await NFTOracle.deploy(20, 1);
  await nftOracle.deployed();
  console.log("NFT Oracle Address:", nftOracle.address);
  const AddressesProvider = await ethers.getContractFactory(
    "MarketAddressesProvider"
  );
  const addressesProvider = await AddressesProvider.deploy();
  await addressesProvider.deployed();
  console.log("Addresses Provider Address:", addressesProvider.address);
  const DebtToken = await ethers.getContractFactory("DebtToken");
  debtToken = await DebtToken.deploy(
    "DEBT TOKEN",
    "DEBT",
    addressesProvider.address
  );
  await debtToken.deployed();
  console.log("Debt Token Address:", debtToken.address);
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
  const setLoanCenterTx = await addressesProvider.setLoanCenter(
    loanCenter.address
  );
  await setLoanCenterTx.wait();
  const setFeeTreasuryTx = await addressesProvider.setFeeTreasury(
    "0xAE46CbeB042ed76700357c34BB96a7dd33fc543B"
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
    2000,
    9000,
    200
  );
  await initReserveTx.wait();

  // Add reserve to market
  const addReserveTx = await market.addReserve(
    testToken.address,
    testReserve.address
  );
  await addReserveTx.wait();

  //Add test NFT to oracle
  const addNftToOracleTx = await nftOracle.addSupportedNft(
    testNFT.address,
    "500000000000000000000",
    2000
  );
  await addNftToOracleTx.wait();

  //Approve Test loan center nft for use by market
  const approveNFTCollectionTx = await loanCenter.approveNFTCollection(
    testNFT.address
  );
  await approveNFTCollectionTx.wait();
};

function loadTest() {
  before(loadEnv);
}

exports.loadTest = loadTest;
exports.loadEnv = loadEnv;
