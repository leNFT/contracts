const { ethers } = require("hardhat");
const hre = require("hardhat");

async function main() {
  let contractAddresses = require("../../lenft-interface/contractAddresses.json");
  let chainID = hre.network.config.chainId;
  let addresses = contractAddresses["0x" + chainID.toString(16)];

  // Get NFT Oracle
  const NFTOracle = await ethers.getContractFactory("NFTOracle");
  const nftOracle = NFTOracle.attach(addresses.NFTOracle);

  // Check if source is trusted
  const source = "0x9045B6aBC5D3BCccbD451aaaF727CAE0E816D817";
  const addNftToOracleTx = await nftOracle.isSourceTrusted(source);
  console.log("isSourceTrusted", addNftToOracleTx);
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
