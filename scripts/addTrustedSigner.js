const { ethers } = require("hardhat");
const hre = require("hardhat");
require("dotenv").config();

async function main() {
  let contractAddresses = require("../../lenft-interface/contractAddresses.json");
  let chainID = hre.network.config.chainId;
  let addresses = contractAddresses[chainID];

  // Set trusted price signer
  const NFTOracle = await ethers.getContractFactory("NFTOracle");
  const nftOracle = NFTOracle.attach(addresses.NFTOracle);
  const setTrustedPriceSourceTx = await nftOracle.setTrustedPriceSigner(
    process.env.SERVER_ADDRESS,
    true
  );
  await setTrustedPriceSourceTx.wait();
  console.log(
    "Added " + process.env.SERVER_ADDRESS + " to trusted price signers."
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
