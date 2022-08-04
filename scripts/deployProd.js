// We require the Hardhat Runtime Environment explicitly here. This is optional
// but useful for running the script in a standalone fashion through `node <script>`.
//
// When running the script with `npx hardhat run <script>` you'll find the Hardhat
// Runtime Environment's members available in the global scope.
// const hre = require("hardhat");

async function main() {
  // Hardhat always runs the compile task when running scripts with its command
  // line interface.
  //
  // If this script is run directly using `node` you may want to call compile
  // manually to make sure everything is compiled
  // await hre.run('compile');

  /****************************************************************
  DEPLOY LIBRARIES
  They will then be linked to the contracts that use them
  ******************************************************************/

  // Deploy validation logic lib
  ValidationLogicLib = await ethers.getContractFactory("ValidationLogic");
  validationLogicLib = await ValidationLogicLib.deploy();
  console.log("Validation Logic Lib Address:", validationLogicLib.address);

  // Deploy supply logic lib
  SupplyLogicLib = await ethers.getContractFactory("SupplyLogic", {
    libraries: {
      ValidationLogic: validationLogicLib.address,
    },
  });
  supplyLogicLib = await SupplyLogicLib.deploy();
  console.log("Supply Logic Lib Address:", supplyLogicLib.address);

  // Deploy borrow logic lib
  BorrowLogicLib = await ethers.getContractFactory("BorrowLogic", {
    libraries: {
      ValidationLogic: validationLogicLib.address,
    },
  });
  borrowLogicLib = await BorrowLogicLib.deploy();
  console.log("Borrow Logic Lib Address:", borrowLogicLib.address);

  // Deploy liquidation logic lib
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
  const addressesProvider = await upgrades.deployProxy(AddressesProvider);
  console.log("Addresses Provider Proxy Address:", addressesProvider.address);

  // Deploy and initialize market proxy
  const Market = await ethers.getContractFactory("Market", {
    libraries: {
      BorrowLogic: borrowLogicLib.address,
      LiquidationLogic: liquidationLogicLib.address,
      SupplyLogic: supplyLogicLib.address,
    },
  });
  const market = await upgrades.deployProxy(
    Market,
    [addressesProvider.address],
    { unsafeAllow: ["external-library-linking"] }
  );
  console.log("Market Proxy Address:", market.address);

  // Deploy and initialize loan center provider proxy
  const LoanCenter = await ethers.getContractFactory("LoanCenter");
  const loanCenter = await upgrades.deployProxy(LoanCenter, [
    addressesProvider.address,
  ]);
  console.log("Loan Center Proxy Address:", loanCenter.address);

  // Deploy and initialize the debt token
  const DebtToken = await ethers.getContractFactory("DebtToken");
  const debtToken = await upgrades.deployProxy(DebtToken, [
    addressesProvider.address,
    "LDEBT TOKEN",
    "LDEBT",
  ]);
  console.log("Debt Token Proxy Address:", debtToken.address);

  // Deploy and initialize the native token
  const NativeToken = await ethers.getContractFactory("NativeToken");
  const nativeToken = await upgrades.deployProxy(NativeToken, [
    addressesProvider.address,
    "leNFT Token",
    "LE",
    "100000000000000000000000000", //100M Max Cap
  ]);
  console.log("Native Token Proxy Address:", nativeToken.address);

  // Deploy and initialize the native token vault
  const NativeTokenVault = await ethers.getContractFactory("NativeTokenVault", {
    libraries: {
      ValidationLogic: validationLogicLib.address,
    },
  });
  const nativeTokenVault = await upgrades.deployProxy(
    NativeTokenVault,
    [addressesProvider.address, nativeToken.address, "veleNFT Token", "veLE"],
    { unsafeAllow: ["external-library-linking"] }
  );
  console.log("Native Token Vault Proxy Address:", nativeTokenVault.address);

  /****************************************************************
  DEPLOY NON-PROXY CONTRACTS
  Deploy contracts that are not updatable
  ******************************************************************/

  // Deploy the Interest Rate contract
  const InterestRate = await ethers.getContractFactory("InterestRate");
  interestRate = await InterestRate.deploy(8000, 1000, 2500, 10000);
  await interestRate.deployed();
  console.log("Interest Rate Address:", interestRate.address);

  // Deploy the NFT Oracle contract
  const NFTOracle = await ethers.getContractFactory("NFTOracle");
  nftOracle = await NFTOracle.deploy(addressesProvider.address, 2000, 1); //Max Price deviation (20%) and min update time
  await nftOracle.deployed();
  console.log("NFT Oracle Address:", nftOracle.address);

  // Deploy TokenOracle contract
  const TokenOracle = await ethers.getContractFactory("TokenOracle");
  tokenOracle = await TokenOracle.deploy();
  await tokenOracle.deployed();
  console.log("Token Oracle Address:", tokenOracle.address);

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
  console.log("Set Native Token / ETH to 100000000000000");

  //Set every address in the address provider
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
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
