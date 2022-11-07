const { ethers } = require("hardhat");
const hre = require("hardhat");
require("dotenv").config();

async function main() {
  let contractAddresses = require("../../lenft-interface/contractAddresses.json");
  let chainID = hre.network.config.chainId;
  let addresses = contractAddresses[chainID.toString(16)];
  let reserve = "0xA3e4910880cfCb8E1929b6B9a6B03DcE6312329a";

  // Add NFT to oracle
  const GenesisNFT = await ethers.getContractFactory("GenesisNFT");
  const genesisNFT = GenesisNFT.attach(addresses.GenesisNFT);

  // Set trusted price source
  const setMintDepositReserveTx = await genesisNFT.setMintDepositReserve(
    reserve
  );
  await setMintDepositReserveTx.wait();
  console.log("Set " + reserve + " as genesis mint deposit reserve.");
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
