const { ethers } = require("hardhat");
const hre = require("hardhat");
require("dotenv").config();

async function main() {
  let contractAddresses = require("../../lenft-interface/contractAddresses.json");
  let chainID = hre.network.config.chainId;
  let addresses = contractAddresses[chainID.toString(16)];
  let pool = "0x1961f37B1D8aB2422968Bc8E10B056530368aE56";

  // Add NFT to oracle
  const GenesisNFT = await ethers.getContractFactory("GenesisNFT");
  const genesisNFT = GenesisNFT.attach(addresses.GenesisNFT);

  // Set trusted price source
  const setIncentivizedPoolTx = await genesisNFT.setTradingPool(pool);
  await setIncentivizedPoolTx.wait();
  console.log("Set " + pool + " as genesis incentivized pool.");
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
