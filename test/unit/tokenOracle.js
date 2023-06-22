const { expect } = require("chai");
const { time } = require("@nomicfoundation/hardhat-network-helpers");
const { ethers } = require("hardhat");
const { BigNumber } = require("ethers");
const helpers = require("@nomicfoundation/hardhat-network-helpers");
const load = require("../helpers/_loadTest.js");
const { getPriceSig, priceSigner } = require("../helpers/getPriceSig.js");
const { parse } = require("dotenv");

describe("TokenOracle", function () {
  const testDataFeed = "0x5f4ec3df9cbd43714fe2740f5e3616155c5b8419"; // Price feed for ETH/USD
  const testTokenAddress = "0x853d955aCEf822Db058eb8505911ED77F175b99e";

  // Dont need to call the entire loadTestAlways function since the setup is only the tokenOracle deployment
  before(async () => {
    // Go to a mainnet fork so we can test the oracle data feed
    await helpers.reset(
      "https://mainnet.infura.io/v3/" + process.env.INFURA_API_KEY,
      17253963 // Block number 13/05/2023
    );
    TokenOracle = await ethers.getContractFactory("TokenOracle");
    [owner] = await ethers.getSigners();
    tokenOracle = await TokenOracle.deploy();
    await tokenOracle.deployed();

    // Take a snapshot before the tests start
    snapshotId = await ethers.provider.send("evm_snapshot", []);
  });

  beforeEach(async function () {
    // Restore the blockchain state to the snapshot before each test
    await ethers.provider.send("evm_revert", [snapshotId]);

    // Take a snapshot before the tests start
    snapshotId = await ethers.provider.send("evm_snapshot", []);
  });

  it("Should be able to add a token's datafeed", async function () {
    expect(await tokenOracle.isTokenSupported(testTokenAddress)).to.equal(
      false
    );
    // Add the token's datafeed
    const tx = await tokenOracle.setTokenETHDataFeed(
      testTokenAddress,
      testDataFeed
    );
    await tx.wait();

    expect(await tokenOracle.isTokenSupported(testTokenAddress)).to.equal(true);

    // Remove the token's datafeed
    const tx2 = await tokenOracle.setTokenETHDataFeed(
      testTokenAddress,
      ethers.constants.AddressZero
    );
    await tx2.wait();

    expect(await tokenOracle.isTokenSupported(testTokenAddress)).to.equal(
      false
    );
  });
  it("Should be able to add a token's ETH price", async function () {
    expect(await tokenOracle.isTokenSupported(testTokenAddress)).to.equal(
      false
    );
    // Add the token's ETH price
    const tx = await tokenOracle.setTokenETHPrice(
      testTokenAddress,
      ethers.utils.parseEther("1")
    );
    await tx.wait();

    expect(await tokenOracle.isTokenSupported(testTokenAddress)).to.equal(true);

    // Remove the token's ETH price
    const tx2 = await tokenOracle.setTokenETHPrice(
      testTokenAddress,
      ethers.constants.AddressZero
    );
    await tx2.wait();

    expect(await tokenOracle.isTokenSupported(testTokenAddress)).to.equal(
      false
    );
  });
  it("Should be able to get a token ETH price from the saved prices", async function () {
    // Add the token's ETH price
    const tx = await tokenOracle.setTokenETHPrice(
      testTokenAddress,
      ethers.utils.parseEther("1")
    );
    await tx.wait();

    // Get the token from the saved prices
    expect((await tokenOracle.getTokenETHPrice(testTokenAddress))[0]).to.equal(
      ethers.utils.parseEther("1")
    );

    // Add the token's datafeed
    const tx2 = await tokenOracle.setTokenETHDataFeed(
      testTokenAddress,
      testDataFeed
    );
    await tx2.wait();

    // Get the price from the datafeed
    expect(
      (await tokenOracle.getTokenETHPrice(testTokenAddress))[0]
    ).to.be.above(ethers.utils.parseEther("1"));

    // Remove the token's DATA feed
    const tx3 = await tokenOracle.setTokenETHDataFeed(
      testTokenAddress,
      ethers.constants.AddressZero
    );
    await tx3.wait();

    // Get the token from the saved prices
    expect((await tokenOracle.getTokenETHPrice(testTokenAddress))[0]).to.equal(
      ethers.utils.parseEther("1")
    );

    // Remove the token's ETH price
    const tx4 = await tokenOracle.setTokenETHPrice(testTokenAddress, 0);
    await tx4.wait();

    // expect an error to be thrown
    await expect(
      tokenOracle.getTokenETHPrice(testTokenAddress)
    ).to.be.revertedWith("TO:GTEP:TOKEN_NOT_SUPPORTED");
  });
});
