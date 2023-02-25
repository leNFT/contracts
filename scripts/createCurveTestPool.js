// We require the Hardhat Runtime Environment explicitly here. This is optional
// but useful for running the script in a standalone fashion through `node <script>`.
//
// When running the script with `npx hardhat run <script>` you'll find the Hardhat
// Runtime Environment's members available in the global scope.

const { ethers } = require("hardhat");

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

  const Pool = await ethers.getContractFactory("CurvePool");
  console.log("Deploying CurvePool...");
  const pool = await Pool.deploy();
  await pool.deployed();
  console.log("Pool address: ", pool.address);

  // Init pool
  const initPoolTx = await pool.initialize(
    "leNFT",
    "LE",
    [
      "0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE", // Burn address
      addresses.NativeToken,
      ethers.constants.AddressZero,
      ethers.constants.AddressZero,
    ],
    [ethers.utils.parseUnits("1", 18), ethers.utils.parseUnits("1", 18), 0, 0],
    10000,
    300
  );
  await initPoolTx.wait();

  console.log("Initialized pool");

  const GenesisNFT = await ethers.getContractFactory("GenesisNFT");
  const genesisNFT = GenesisNFT.attach(addresses.GenesisNFT);

  // Set trusted price source
  const setIncentivizedPoolTx = await genesisNFT.setTradingPool(pool.address);
  await setIncentivizedPoolTx.wait();
  console.log("Set " + pool.address + " as genesis incentivized pool.");

  // Write pool address to file
  const fs = require("fs");
  addresses.CurvePool = pool.address;
  contractAddresses[chainID.toString(16)] = addresses;
  fs.writeFileSync(
    "../lenft-interface/contractAddresses.json",
    JSON.stringify(contractAddresses),
    function (err) {
      if (err) throw err;
      console.log("File written to interface folder");
    }
  );
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
