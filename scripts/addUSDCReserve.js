const { ethers } = require("hardhat");

async function main() {
  let contractAddresses = require("../../lenft-interface/contractAddresses.json");
  let chainID = "0x5";
  let addresses = contractAddresses[chainID];

  // Deploy and init eth reserve
  const USDCReserve = await ethers.getContractFactory("Reserve", {
    libraries: {
      SupplyLogic: addresses.SupplyLogicLib,
    },
  });
  const usdcReserve = await upgrades.deployProxy(
    USDCReserve,
    [
      addresses.AddressesProvider,
      addresses["USDC"].address,
      "RESERVEUSDC",
      "RUSDC",
      8000, //80%
      2000, //20%
      200, //2%
      100000000, //Underlying safeguard, can deposit up to 100 USDC
    ],
    { unsafeAllow: ["external-library-linking"] }
  );
  console.log("USDC Reserve Initialized");

  // Add reserve to market
  const Market = await ethers.getContractFactory("Market", {
    libraries: {
      BorrowLogic: addresses.BorrowLogicLib,
      LiquidationLogic: addresses.LiquidationLogicLib,
      SupplyLogic: addresses.SupplyLogicLib,
    },
  });
  const market = Market.attach(addresses.Market);

  await market.addReserve(addresses["USDC"].address, usdcReserve.address);

  console.log("Added USDC Reserve", usdcReserve.address);

  //Add a price to ETH using the token oracle (will always be 1)
  const TokenOracle = await ethers.getContractFactory("TokenOracle");
  const tokenOracle = TokenOracle.attach(addresses.TokenOracle);
  const setUSDCPriceTx = await tokenOracle.addTokenETHDataFeed(
    addresses["USDC"].address,
    addresses["USDC"].priceFeed
  );
  await setUSDCPriceTx.wait();

  console.log("ETH/USD data feed set");
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
