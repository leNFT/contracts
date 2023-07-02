const { expect } = require("chai");
const { ethers } = require("hardhat");
const load = require("../helpers/_loadTest.js");

describe("exponentialCurve", function () {
  load.loadTest(false);

  before(async function () {
    // Take a snapshot before the tests start
    snapshotId = await ethers.provider.send("evm_snapshot", []);
  });

  it("Should calculate the correct price after buying", async function () {
    const price = ethers.utils.parseEther("1");
    const delta = 500;
    const expectedPrice = ethers.utils.parseEther("1.05");

    const newPrice = await exponentialCurve.priceAfterBuy(price, delta, 0);
    expect(newPrice).to.equal(expectedPrice);
  });

  it("Should calculate the correct price after selling", async function () {
    const price = ethers.utils.parseEther("1");
    const delta = 500;
    const expectedPrice = ethers.utils.parseEther("0.952380952380952381");

    const newPrice = await exponentialCurve.priceAfterSell(price, delta, 0);
    expect(newPrice).to.equal(expectedPrice);
  });

  it("Should revert when validating LP parameters with invalid price", async function () {
    await expect(
      exponentialCurve.validateLpParameters(0, 1, 1)
    ).to.be.revertedWith("EPC:VLPP:INVALID_PRICE");
  });

  it("Should revert when validating LP parameters with invalid delta", async function () {
    const price = ethers.utils.parseEther("1");
    const invalidDelta = 10000; // Greater than PercentageMath.PERCENTAGE_FACTOR
    const fee = 1;

    await expect(
      exponentialCurve.validateLpParameters(price, invalidDelta, fee)
    ).to.be.revertedWith("EPC:VLPP:INVALID_DELTA");
  });

  it("Should revert when validating LP parameters with invalid fee-delta ratio", async function () {
    const price = ethers.utils.parseEther("1");
    const delta = 60;
    const invalidFee = 20;

    await expect(
      exponentialCurve.validateLpParameters(price, delta, invalidFee)
    ).to.be.revertedWith("EPC:VLPP:INVALID_FEE_DELTA_RATIO");
  });
});
