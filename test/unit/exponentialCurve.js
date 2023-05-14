const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("ExponentialPriceCurve", function () {
  let ExponentialPriceCurve, exponentialPriceCurve, owner;

  beforeEach(async () => {
    ExponentialPriceCurve = await ethers.getContractFactory(
      "ExponentialPriceCurve"
    );
    [owner] = await ethers.getSigners();
    exponentialPriceCurve = await ExponentialPriceCurve.deploy();
    await exponentialPriceCurve.deployed();
  });

  it("Should calculate the correct price after buying", async function () {
    const price = ethers.utils.parseEther("1");
    const delta = 500;
    const expectedPrice = ethers.utils.parseEther("1.05");

    const newPrice = await exponentialPriceCurve.priceAfterBuy(price, delta, 0);
    expect(newPrice).to.equal(expectedPrice);
  });

  it("Should calculate the correct price after selling", async function () {
    const price = ethers.utils.parseEther("1");
    const delta = 500;
    const expectedPrice = ethers.utils.parseEther("0.95238095238095238");

    const newPrice = await exponentialPriceCurve.priceAfterSell(
      price,
      delta,
      0
    );
    expect(newPrice).to.equal(expectedPrice);
  });

  it("Should revert when validating LP parameters with invalid price", async function () {
    await expect(
      exponentialPriceCurve.validateLpParameters(0, 1, 1)
    ).to.be.revertedWith("EPC:VLPP:INVALID_PRICE");
  });

  it("Should revert when validating LP parameters with invalid delta", async function () {
    const price = ethers.utils.parseEther("1");
    const invalidDelta = 10000; // Greater than PercentageMath.PERCENTAGE_FACTOR
    const fee = 1;

    await expect(
      exponentialPriceCurve.validateLpParameters(price, invalidDelta, fee)
    ).to.be.revertedWith("EPC:VLPP:INVALID_DELTA");
  });

  it("Should revert when validating LP parameters with invalid fee-delta ratio", async function () {
    const price = ethers.utils.parseEther("1");
    const delta = 60;
    const invalidFee = 20;

    await expect(
      exponentialPriceCurve.validateLpParameters(price, delta, invalidFee)
    ).to.be.revertedWith("EPC:VLPP:INVALID_FEE_DELTA_RATIO");
  });
});
