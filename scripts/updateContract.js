const { ethers, upgrades } = require("hardhat");

async function main() {
  const address = "0x28c8fABa0976785808D05a9076edBaec6D535f69";
  const Contract = await ethers.getContractFactory("VotingEscrow");
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
