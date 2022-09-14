const { ethers } = require("hardhat");
const hre = require("hardhat");

async function main() {
  let contractAddresses = require("../../lenft-interface/contractAddresses.json");
  let chainID = hre.network.config.chainId;
  let addresses = contractAddresses[chainID.toString(16)];

  // Create TEST NFT contract
  // const TestNFT = await ethers.getContractFactory("TestNFT");
  // const testNFT = await TestNFT.deploy("TEST NFT", "TNFT");
  // await testNFT.deployed();
  // console.log("Deployed TEST NFT to", testNFT.address);

  const newSupportedCollectionAddress =
    "0x0171dB1e3Cc005d2A6E0BA531509D007a5B8C1a8";
  const maxCollaterization = 5000;

  // // Add NFT to oracle
  const NFTOracle = await ethers.getContractFactory("NFTOracle");
  const nftOracle = NFTOracle.attach(addresses.NFTOracle);

  const addNftToOracleTx = await nftOracle.addSupportedCollection(
    newSupportedCollectionAddress,
    maxCollaterization
  );
  await addNftToOracleTx.wait();
  console.log(
    "Added " +
      newSupportedCollectionAddress +
      " to Oracle with " +
      maxCollaterization / 100 +
      "% max collaterization"
  );

  // Approve NFT to be used by loan center
  const LoanCenter = await ethers.getContractFactory("LoanCenter");
  const loanCenter = LoanCenter.attach(addresses.LoanCenter);
  const approveNFTCollectionTx = await loanCenter.approveNFTCollection(
    newSupportedCollectionAddress
  );
  await approveNFTCollectionTx.wait();
  console.log("Approved collection to be used by loan center");
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
