const { ethers, upgrades } = require("hardhat");

async function main() {
  const address = "0x5FbDB2315678afecb367f032d93F642f64180aa3";
  const Contract = await ethers.getContractFactory("GenesisNFT");
  console.log("Upgrading Contract...");
  await upgrades.upgradeProxy(address, Contract);
  console.log("Contract upgraded");
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
