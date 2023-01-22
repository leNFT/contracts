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
  console.log("chainID: ", chainID);
  var addresses = contractAddresses[chainID.toString(16)];
  const tradingPool = "0x91b196c824D38C536698dEb8cF2AAb426870FD50";

  // Deploy gauge
  const Gauge = await ethers.getContractFactory("TradingGauge");
  const gauge = await Gauge.deploy(addresses.AddressesProvider, tradingPool);
  await gauge.deployed();
  console.log("Gauge address: ", gauge.address);

  // Add gauge to gauge controller
  const GaugeController = await ethers.getContractFactory("GaugeController");
  const gaugeController = GaugeController.attach(addresses.GaugeController);

  const setAddGaugeTx = await gaugeController.addGauge(gauge.address);
  await setAddGaugeTx.wait();
  console.log("Added Gauge to Gauge Controller.");
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
