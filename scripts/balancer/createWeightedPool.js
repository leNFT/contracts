// We require the Hardhat Runtime Environment explicitly here. This is optional
// but useful for running the script in a standalone fashion through `node <script>`.
//
// When running the script with `npx hardhat run <script>` you'll find the Hardhat
// Runtime Environment's members available in the global scope.

const { ethers } = require("hardhat");
const weightedPoolFactoryABI = require("./weightedPoolFactoryABI.json");

// const hre = require("hardhat");
require("dotenv").config();

async function main() {
  // Hardhat always runs the compile task when running scripts with its command
  // line interface.
  //
  // If this script is run directly using `node` you may want to call compile
  // manually to make sure everything is compiled
  // await hre.run('compile');
  var contractAddresses = require("../../../lenft-interface/contractAddresses.json");
  let chainID = hre.network.config.chainId;
  console.log("chainID: ", chainID);
  var addresses = contractAddresses[chainID.toString(16)];
  const poolFactoryAddress = "0x26575A44755E0aaa969FDda1E4291Df22C5624Ea";
  const vaultAddress = "0xBA12222222228d8Ba445958a75a0704d566BF2C8";
  const queryAddress = "0xE39B5e3B6D74016b2F6A9673D7d7493B6DF549d5";

  const factoryContract = await ethers.getContractAt(
    weightedPoolFactoryABI,
    poolFactoryAddress
  );

  console.log("Deploying Balancer pool...");
  console.log("LE address: ", addresses.NativeToken);
  console.log("WETH address: ", addresses.ETH.address);
  const createTx = await factoryContract.create(
    "Balancer Pool 80 LE 20 WETH",
    "B-80LE-20WETH",
    [addresses.ETH.address, addresses.NativeToken],
    ["200000000000000000", "800000000000000000"],
    [ethers.constants.AddressZero, ethers.constants.AddressZero],
    "2500000000000000",
    "0xba1ba1ba1ba1ba1ba1ba1ba1ba1ba1ba1ba1ba1b"
  );
  const createTxReceipt = await createTx.wait();
  const poolId = createTxReceipt.logs[1].topics[1];
  const poolAddress = poolId.slice(0, 42);

  console.log("BalancerPool deployed with ID: ", poolId);
  console.log("BalancerPool deployed at address: ", poolAddress);

  const GenesisNFT = await ethers.getContractFactory("GenesisNFT");
  console.log("GenesisNFT address: ", addresses.GenesisNFT);
  const genesisNFT = GenesisNFT.attach(addresses.GenesisNFT);
  const balancerDetails = {
    poolId: poolId,
    pool: poolAddress,
    vault: vaultAddress,
    queries: queryAddress,
  };
  console.log("Balancer details: ", balancerDetails);

  // Set balancer details
  const setBalancerDetailsTx = await genesisNFT.setBalancerDetails(
    balancerDetails
  );
  await setBalancerDetailsTx.wait();
  console.log("Set Balancer details");

  // Write pool id to file
  const fs = require("fs");
  addresses.BalancerPool = poolAddress;
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
