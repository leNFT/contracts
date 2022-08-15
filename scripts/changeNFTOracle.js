const { ethers } = require("hardhat");
const hre = require("hardhat");
require("dotenv").config();

async function main() {
  let contractAddresses = require("../../lenft-interface/contractAddresses.json");
  let chainID = hre.network.config.chainId;
  let addresses = contractAddresses["0x" + chainID.toString(16)];

  // Add NFT to oracle
  const AddressesProvider = await ethers.getContractFactory(
    "AddressesProvider"
  );
  const addressesProvider = AddressesProvider.attach(
    addresses.AddressesProvider
  );

  const setNFTOracleTx = await addressesProvider.setNFTOracle(
    addresses.NFTOracle
  );
  await setNFTOracleTx.wait();
  console.log("Set New NFT oracle");
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
