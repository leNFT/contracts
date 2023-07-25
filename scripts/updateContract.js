const { ethers, upgrades } = require("hardhat");

async function main() {
  const proxyAddress = "0x11FDA9d7aB540309f7292f2dc504C105Fb565173";
  const addressProviderAddress = "0x4Df583E7D80336cb9EE91c381A939aEE58404567";
  const Contract = await ethers.getContractFactory("GaugeController");
  console.log("Upgrading Contract...");
  await upgrades.upgradeProxy(proxyAddress, Contract, {
    unsafeAllow: ["state-variable-immutable"],
    constructorArgs: [addressProviderAddress],
  });
  console.log("Contract upgraded");
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
