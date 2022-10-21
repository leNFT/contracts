const { ethers } = require("hardhat");
const hre = require("hardhat");
require("dotenv").config();

async function main() {
  let contractAddresses = require("../../lenft-interface/contractAddresses.json");
  let chainID = hre.network.config.chainId;
  let addresses = contractAddresses[chainID.toString(16)];

  const collection = "0xf5de760f2e916647fd766B4AD9E85ff943cE3A2b";
  const asset = addresses.ETH.address;
  const reserve = "0x5065d69b5e05b85c1201B6A946c150BD6fF2B46B";

  const Market = await ethers.getContractFactory("Market", {
    libraries: {
      BorrowLogic: addresses.BorrowLogicLib,
      LiquidationLogic: addresses.LiquidationLogicLib,
      SupplyLogic: addresses.SupplyLogicLib,
    },
  });
  const market = Market.attach(addresses.Market);

  // Set reserve
  const setReserveTx = await market.setReserve(collection, asset, reserve);
  await setReserveTx.wait();
  console.log("collection", collection);
  console.log("asset", asset);
  console.log("reserve", reserve);
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
