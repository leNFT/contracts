const { expect } = require("chai");
const { time } = require("@nomicfoundation/hardhat-network-helpers");
const { ethers } = require("hardhat");
const { BigNumber } = require("ethers");
const load = require("../helpers/_loadTest.js");
const { getPriceSig, priceSigner } = require("../helpers/getPriceSig.js");
const { parse } = require("dotenv");

describe("TokenOracle", function () {
  load.loadTestAlways(true);

  const testDataFeed = "0x1b44F3514812d835EB1BDB0acB33d3fA3351Ee43";

  it("Should be able to add a token's datafeed", async function () {
    expect(await tokenOracle.isTokenSupported(wethAddress)).to.equal(false);
    // Add the token's datafeed
    const tx = await tokenOracle.setTokenETHDataFeed(wethAddress, testDataFeed);
    await tx.wait();

    expect(await tokenOracle.isTokenSupported(wethAddress)).to.equal(true);

    // Remove the token's datafeed
    const tx2 = await tokenOracle.setTokenETHDataFeed(
      wethAddress,
      ethers.constants.AddressZero
    );
    await tx2.wait();

    expect(await tokenOracle.isTokenSupported(wethAddress)).to.equal(false);
  });
  it("Should be able to add a token's ETH price", async function () {
    expect(await tokenOracle.isTokenSupported(wethAddress)).to.equal(false);
    // Add the token's ETH price
    const tx = await tokenOracle.setTokenETHPrice(
      wethAddress,
      ethers.utils.parseEther("1")
    );
    await tx.wait();

    expect(await tokenOracle.isTokenSupported(wethAddress)).to.equal(true);

    // Remove the token's ETH price
    const tx2 = await tokenOracle.setTokenETHPrice(
      wethAddress,
      ethers.constants.AddressZero
    );
    await tx2.wait();

    expect(await tokenOracle.isTokenSupported(wethAddress)).to.equal(false);
  });
  it("Should be able to get a token ETH price", async function () {
    // Add the token's ETH price
    const tx = await tokenOracle.setTokenETHPrice(
      wethAddress,
      ethers.utils.parseEther("1")
    );
    await tx.wait();

    // Get the token from the saved prices
    expect(await tokenOracle.getTokenETHPrice(wethAddress)).to.equal(
      ethers.utils.parseEther("1")
    );

    // Add the token's datafeed
    const tx2 = await tokenOracle.setTokenETHDataFeed(
      wethAddress,
      testDataFeed
    );
    await tx2.wait();

    // Get the price from the datafeed
    expect(await tokenOracle.getTokenETHPrice(wethAddress)).to.be.greaterThan(
      ethers.utils.parseEther("1")
    );

    // Remove the token's DATA feed
    const tx3 = await tokenOracle.setTokenETHDataFeed(
      wethAddress,
      ethers.constants.AddressZero
    );
    await tx3.wait();

    // Get the token from the saved prices
    expect(await tokenOracle.getTokenETHPrice(wethAddress)).to.equal(
      ethers.utils.parseEther("1")
    );

    // Remove the token's ETH price
    const tx4 = await tokenOracle.setTokenETHPrice(wethAddress, 0);
    await tx4.wait();

    // expect an error to be thrown
    await expect(tokenOracle.getTokenETHPrice(wethAddress)).to.be.revertedWith(
      "TO:GTEP:TOKEN_NOT_SUPPORTED"
    );
  });
});
