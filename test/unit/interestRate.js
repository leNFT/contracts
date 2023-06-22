const { expect } = require("chai");
const { ethers } = require("hardhat");
const { BigNumber } = require("ethers");

describe("InterestRate", function () {
  let InterestRate, interestRate, owner;
  const tokenAddress = "0x742d35Cc6634C0532925a3b844Bc454e4438f44e"; // Example token address
  // Example interest rate config

  let optimalUtilizationRate = 8000;
  let baseBorrowRate = 1000;
  let lowSlope = 2000;
  let highSlope = 3000;
  beforeEach(async () => {
    InterestRate = await ethers.getContractFactory("InterestRate");
    [owner] = await ethers.getSigners();
    interestRate = await InterestRate.deploy();
    await interestRate.deployed();
  });

  it("Should add a token with correct interest rate config", async function () {
    const tx = await interestRate.addToken(
      tokenAddress,
      optimalUtilizationRate,
      baseBorrowRate,
      lowSlope,
      highSlope
    );
    await tx.wait();

    console.log("Getting config");

    const storedConfig = await interestRate.getInterestRateConfig(tokenAddress);
    expect(storedConfig.optimalUtilizationRate).to.equal(
      optimalUtilizationRate
    );
    expect(storedConfig.baseBorrowRate).to.equal(baseBorrowRate);
    expect(storedConfig.lowSlope).to.equal(lowSlope);
    expect(storedConfig.highSlope).to.equal(highSlope);
    expect(await interestRate.isTokenSupported(tokenAddress)).to.equal(true);
  });

  it("Should remove a token and its interest rate config", async function () {
    const tx = await interestRate.addToken(
      tokenAddress,
      optimalUtilizationRate,
      baseBorrowRate,
      lowSlope,
      highSlope
    );
    await tx.wait();

    const removeTx = await interestRate.removeToken(tokenAddress);
    await removeTx.wait();

    expect(await interestRate.isTokenSupported(tokenAddress)).to.equal(false);

    // Expect an error to be thrown if we remove the token again
    await expect(interestRate.removeToken(tokenAddress)).to.be.revertedWith(
      "IR:TOKEN_NOT_SUPPORTED"
    );
  });

  it("Should return correct supported status for a token", async function () {
    expect(await interestRate.isTokenSupported(tokenAddress)).to.equal(false);

    await interestRate.addToken(
      tokenAddress,
      optimalUtilizationRate,
      baseBorrowRate,
      lowSlope,
      highSlope
    );

    const isSupportedAfter = await interestRate.isTokenSupported(tokenAddress);
    expect(isSupportedAfter).to.equal(true);
  });
  it("Should return the correct interest rate config", async function () {
    const tx = await interestRate.addToken(
      tokenAddress,
      optimalUtilizationRate,
      baseBorrowRate,
      lowSlope,
      highSlope
    );
    await tx.wait();

    const storedConfig = await interestRate.getInterestRateConfig(tokenAddress);
    expect(storedConfig.optimalUtilizationRate).to.equal(
      optimalUtilizationRate
    );
    expect(storedConfig.baseBorrowRate).to.equal(baseBorrowRate);
    expect(storedConfig.lowSlope).to.equal(lowSlope);
    expect(storedConfig.lowSlope).to.equal(lowSlope);

    const removeTx = await interestRate.removeToken(tokenAddress);
    await removeTx.wait();

    // Expecting an error to be thrown if we try to get the config for the removed token
    await expect(
      interestRate.getInterestRateConfig(tokenAddress)
    ).to.be.revertedWith("IR:TOKEN_NOT_SUPPORTED");
  });

  it("Should calculate the correct borrow rate", async function () {
    const tx = await interestRate.addToken(
      tokenAddress,
      optimalUtilizationRate,
      baseBorrowRate,
      lowSlope,
      highSlope
    );
    await tx.wait();

    const assets = BigNumber.from("800000000000000000"); // 0.8 ETH
    const debt = BigNumber.from("200000000000000000"); // 0.2 ETH
    const expectedBorrowRate = 1400;

    const borrowRate = await interestRate.calculateBorrowRate(
      tokenAddress,
      assets,
      debt
    );
    expect(borrowRate).to.equal(expectedBorrowRate);

    // Calculate borrow rate in high slope
    const assets2 = BigNumber.from("100000000000000000"); // 0.1 ETH
    const debt2 = BigNumber.from("900000000000000000"); // 0.9 ETH
    const expectedBorrowRate2 = 2900;

    const borrowRate2 = await interestRate.calculateBorrowRate(
      tokenAddress,
      assets2,
      debt2
    );
    expect(borrowRate2).to.equal(expectedBorrowRate2);

    const removeTx = await interestRate.removeToken(tokenAddress);
    await removeTx.wait();

    // Expecting an error to be thrown if we try to get the config for the removed token
    await expect(
      interestRate.calculateBorrowRate(tokenAddress, assets2, debt2)
    ).to.be.revertedWith("IR:TOKEN_NOT_SUPPORTED");
  });

  it("Should calculate the correct utilization rate", async function () {
    const tx = await interestRate.addToken(
      tokenAddress,
      optimalUtilizationRate,
      baseBorrowRate,
      lowSlope,
      highSlope
    );
    await tx.wait();

    const assets = BigNumber.from("800000000000000000"); // 0.8 ETH
    const debt = BigNumber.from("200000000000000000"); // 0.2 ETH
    const expectedUtilizationRate = 2000; // Example value

    const utilizationRate = await interestRate.calculateUtilizationRate(
      tokenAddress,
      assets,
      debt
    );
    expect(utilizationRate).to.equal(expectedUtilizationRate);

    const removeTx = await interestRate.removeToken(tokenAddress);
    await removeTx.wait();

    // Expecting an error to be thrown if we try to get the config for the removed token
    await expect(
      interestRate.calculateUtilizationRate(tokenAddress, assets, debt)
    ).to.be.revertedWith("IR:TOKEN_NOT_SUPPORTED");
  });

  it("Should return the correct optimal borrow rate", async function () {
    const tx = await interestRate.addToken(
      tokenAddress,
      optimalUtilizationRate,
      baseBorrowRate,
      lowSlope,
      highSlope
    );
    await tx.wait();

    const expectedOptimalBorrowRate = 2600; // from 8000 optimal utilization rate

    const optimalBorrowRate = await interestRate.getOptimalBorrowRate(
      tokenAddress
    );
    expect(optimalBorrowRate).to.equal(expectedOptimalBorrowRate);

    const removeTx = await interestRate.removeToken(tokenAddress);
    await removeTx.wait();

    // Expecting an error to be thrown if we try to get the config for the removed token
    await expect(
      interestRate.getOptimalBorrowRate(tokenAddress)
    ).to.be.revertedWith("IR:TOKEN_NOT_SUPPORTED");
  });
});
