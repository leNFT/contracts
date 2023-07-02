const { ethers, upgrades } = require("hardhat");
var contractAddresses = require("../../lenft-interface/contractAddresses.json");
let chainID = hre.network.config.chainId;

console.log("chainID: ", chainID.toString());
var addresses = contractAddresses[chainID.toString()];

async function main() {
  const Contract = await ethers.getContractFactory("TradingPoolFactory");
  const tradingPoolFactory = Contract.attach(addresses.TradingPoolFactory);

  console.log("Setting current curves to false");

  const tx1 = await tradingPoolFactory.setPriceCurve(
    addresses["ExponentialCurve"],
    false
  );
  await tx1.wait();
  const tx2 = await tradingPoolFactory.setPriceCurve(
    addresses["LinearCurve"],
    false
  );
  await tx2.wait();

  console.log("Deploying new curves.");

  const ExponentialCurve = await ethers.getContractFactory(
    "ExponentialPriceCurve"
  );
  const exponentialCurve = await ExponentialCurve.deploy(
    addresses.AddressProvider
  );
  await exponentialCurve.deployed();
  console.log("Deployed ExponentialCurve", exponentialCurve.address);
  const LinearCurve = await ethers.getContractFactory("LinearPriceCurve");
  const linearCurve = await LinearCurve.deploy(addresses.AddressProvider);
  await linearCurve.deployed();
  console.log("Deployed LinearCurve", linearCurve.address);

  console.log("Setting curves.");

  const setExponentialCurveTx = await tradingPoolFactory.setPriceCurve(
    exponentialCurve.address,
    true
  );
  await setExponentialCurveTx.wait();
  const setLinearCurveTx = await tradingPoolFactory.setPriceCurve(
    linearCurve.address,
    true
  );
  await setLinearCurveTx.wait();
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
