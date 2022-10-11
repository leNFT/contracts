const { ethers } = require("hardhat");
const hre = require("hardhat");
require("dotenv").config();

async function main() {
  let contractAddresses = require("../../lenft-interface/contractAddresses.json");
  let chainID = hre.network.config.chainId;
  let addresses = contractAddresses[chainID.toString(16)];

  const NativeTokenVault = await ethers.getContractFactory("NativeTokenVault", {
    libraries: {
      ValidationLogic: addresses.ValidationLogicLib,
    },
  });
  const nativeTokenVault = NativeTokenVault.attach(addresses.NativeTokenVault);

  // Set liquidation rewards factor
  const setLiquidationRewardFactorTx =
    await nativeTokenVault.setLiquidationRewardFactor("55000000000000000");
  await setLiquidationRewardFactorTx.wait();
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
