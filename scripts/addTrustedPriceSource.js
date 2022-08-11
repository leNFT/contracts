const { ethers } = require("hardhat");
const hre = require("hardhat");
require("dotenv").config();

async function main() {
  let contractAddresses = require("../../lenft-interface/contractAddresses.json");
  let chainID = hre.network.config.chainId;
  let addresses = contractAddresses["0x" + chainID.toString(16)];

  // Add NFT to oracle
  const NFTOracle = await ethers.getContractFactory("NFTOracle");
  const nftOracle = NFTOracle.attach(addresses.NFTOracle);

  // Set trusted price source
  const setTrustedPriceSourceTx = await nftOracle.addTrustedPriceSource(
    process.env.SERVER_ADDRESS
  );
  await setTrustedPriceSourceTx.wait();
  console.log(
    "Added " + process.env.SERVER_ADDRESS + " to trusted price sources."
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
