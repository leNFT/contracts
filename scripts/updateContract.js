const { ethers, upgrades } = require("hardhat");

async function main() {
  const address = "0x5eC3482efb4562fCA96Dc3C4BD1108D771fE70cE";
  const Contract = await ethers.getContractFactory("DebtToken");
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
