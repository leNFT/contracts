const { ethers } = require("hardhat");
const hre = require("hardhat");

async function main() {
  let contractAddresses = require("../../lenft-interface/contractAddresses.json");
  let chainID = hre.network.config.chainId;
  let addresses = contractAddresses[chainID.toString(16)];

  // Deploy and init eth reserve
  const WETHReserve = await ethers.getContractFactory("Reserve", {
    libraries: {
      SupplyLogic: addresses.SupplyLogicLib,
    },
  });
  const wethReserve = await upgrades.deployProxy(
    WETHReserve,
    [
      addresses.AddressesProvider,
      addresses["WETH"].address,
      "RESERVEWETH",
      "RWETH",
      8000, //80%
      2000, //20%
      200, //2%
      "2000000000000000000", //Reserve safeguard, can deposit up to 2 ETH
    ],
    { unsafeAllow: ["external-library-linking"] }
  );
  console.log("WETH Reserve Initialized");

  // Add reserve to market
  const Market = await ethers.getContractFactory("Market", {
    libraries: {
      BorrowLogic: addresses.BorrowLogicLib,
      LiquidationLogic: addresses.LiquidationLogicLib,
      SupplyLogic: addresses.SupplyLogicLib,
    },
  });
  const market = Market.attach(addresses.Market);

  await market.addReserve(addresses["WETH"].address, wethReserve.address);

  console.log("Added wETH Reserve", wethReserve.address);

  //Add a price to ETH using the token oracle (will always be 1)
  const TokenOracle = await ethers.getContractFactory("TokenOracle");
  const tokenOracle = TokenOracle.attach(addresses.TokenOracle);
  const setwETHPriceTx = await tokenOracle.setTokenETHPrice(
    addresses["WETH"].address,
    "1000000000000000000" //1 ETH/wETH, 18 digits precision multiplier
  );
  await setwETHPriceTx.wait();

  console.log("ETH/WETH price set @ 1");
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
