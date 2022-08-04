const { ethers } = require("hardhat");

async function main() {
  let contractAddresses = require("../../lenft-interface/contractAddresses.json");
  let chainID = "0x5";
  let addresses = contractAddresses[chainID];

  // Create TEST NFT contract
  const TestNFT = await ethers.getContractFactory("TestNFT");
  const testNFT = await TestNFT.deploy("TEST NFT", "TNFT");
  await testNFT.deployed();
  console.log("Deployed TEST NFT to", testNFT.address);

  // Add NFT to oracle
  const NFTOracle = await ethers.getContractFactory("NFTOracle");
  const nftOracle = NFTOracle.attach(addresses.NFTOracle);

  const addNftToOracleTx = await nftOracle.addSupportedCollection(
    testNFT.address,
    4000 //max collaterization (40%)
  );
  await addNftToOracleTx.wait();
  console.log("Added TEST NFT to Oracle with 40% max collaterization");

  // Approve NFT to be used by loan center
  const LoanCenter = await ethers.getContractFactory("LoanCenter");
  const loanCenter = LoanCenter.attach(addresses.LoanCenter);
  const approveNFTCollectionTx = await loanCenter.approveNFTCollection(
    testNFT.address
  );
  await approveNFTCollectionTx.wait();
  console.log("Approved TEST NFT to be used by loan center");
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
