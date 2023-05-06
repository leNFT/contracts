const { ethers } = require("hardhat");
const hre = require("hardhat");

async function main() {
  let contractAddresses = require("../../lenft-interface/contractAddresses.json");
  let chainID = hre.network.config.chainId;
  let addresses = contractAddresses[chainID];

  console.log("Adding wETH to token Oracle");

  //Add a price to ETH using the token oracle (will always be 1)
  const TokenOracle = await ethers.getContractFactory("TokenOracle");
  const tokenOracle = TokenOracle.attach(addresses.TokenOracle);
  const setwETHPriceTx = await tokenOracle.setTokenETHPrice(
    addresses["ETH"].address,
    "1000000000000000000" //1 ETH/wETH, 18 digits precision multiplier
  );
  await setwETHPriceTx.wait();

  console.log("ETH/WETH price set @ 1");

  console.log("Adding wETH Interest Rate Model");
  const InterestRate = await ethers.getContractFactory("InterestRate");
  const interestRate = InterestRate.attach(addresses.InterestRate);

  // Add WETH parameters to interest rate contract
  const setWETHInterestRateParamsTx = await interestRate.addToken(
    addresses["ETH"].address,
    {
      optimalUtilizationRate: 7000,
      baseBorrowRate: 500,
      lowSlope: 2000,
      highSlope: 20000,
    }
  );
  await setWETHInterestRateParamsTx.wait();

  console.log("wETH Interest Rate Model added");
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
