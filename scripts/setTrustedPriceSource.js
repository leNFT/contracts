const { ethers } = require("hardhat");

async function main() {
  let contractAddresses = require("../../lenft-interface/contractAddresses.json");
  let chainID = "0x5";
  let addresses = contractAddresses[chainID];
  const priceSource = "0xAE46CbeB042ed76700357c34BB96a7dd33fc543B";

  // Add NFT to oracle
  const NFTOracle = await ethers.getContractFactory("NFTOracle");
  const nftOracle = NFTOracle.attach(addresses.NFTOracle);

  // Set trusted price source
  const setTrustedPriceSourceTx = await nftOracle.setTrustedPriceSource(
    priceSource
  );
  await setTrustedPriceSourceTx.wait();
  console.log("Added " + priceSource + " to trusted price sources.");
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
