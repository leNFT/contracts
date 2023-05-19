const { ethers, upgrades } = require("hardhat");
var contractAddresses = require("../../lenft-interface/contractAddresses.json");
let chainID = hre.network.config.chainId;
console.log("chainID: ", chainID.toString());
var addresses = contractAddresses[chainID.toString()];

async function main() {
  const Contract = await ethers.getContractFactory("NativeTokenTest");
  const contract = Contract.attach(addresses.NativeToken);
  console.log("Running Function...");
  const tx = await contract.mint(
    addresses.NativeTokenFaucet,
    ethers.utils.parseEther("1000000")
  );
  await tx.wait();
  console.log("Done.");
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
