const { expect } = require("chai");
const { ethers } = require("hardhat");
const { Interface } = require("ethers").utils;
const { BigNumber } = require("ethers");

describe("LinearPriceCurve", function () {
  let LinearPriceCurve, linearPriceCurve, owner;

  beforeEach(async () => {
    LinearPriceCurve = await ethers.getContractFactory("LinearPriceCurve");
    [owner] = await ethers.getSigners();
    linearPriceCurve = await LinearPriceCurve.deploy();
    await linearPriceCurve.deployed();
  });

  it("Should calculate the correct price after buying", async function () {
    const price = ethers.utils.parseEther("1");
    const delta = ethers.utils.parseEther("0.5");
    const expectedPrice = ethers.utils.parseEther("1.5");

    const newPrice = await linearPriceCurve.priceAfterBuy(price, delta, 0);
    expect(newPrice).to.equal(expectedPrice);
  });

  it("Should calculate the correct price after selling", async function () {
    const price = ethers.utils.parseEther("1");
    const delta = ethers.utils.parseEther("0.1");
    const fee = 1000;
    const expectedPrice = ethers.utils.parseEther("0.9");

    const newPrice = await linearPriceCurve.priceAfterSell(price, delta, fee);
    expect(newPrice).to.equal(expectedPrice);

    const delta2 = ethers.utils.parseEther("0.5");
    const fee2 = 10;
    const expectedPrice2 = ethers.utils.parseEther("1");
    const newPrice2 = await linearPriceCurve.priceAfterSell(
      price,
      delta2,
      fee2
    );
    expect(newPrice2).to.equal(expectedPrice2);
  });

  it("Should revert when validating LP parameters with invalid price", async function () {
    await expect(
      linearPriceCurve.validateLpParameters(0, 1, 1)
    ).to.be.revertedWith("LPC:VLPP:INVALID_PRICE");
  });

  it("Should revert when validating LP parameters with invalid fee-delta ratio", async function () {
    const price = ethers.utils.parseEther("1");
    const delta = ethers.utils.parseEther("0.1");
    const invalidFee = 20;

    await expect(
      linearPriceCurve.validateLpParameters(price, delta, invalidFee)
    ).to.be.revertedWith("LPC:VLPP:INVALID_FEE_DELTA_RATIO");
  });
});
