const { ethers } = require("hardhat");
const { BigNumber } = require("ethers");
const { expect } = require("chai");
const load = require("../helpers/_loadTest.js");
const Chance = require("chance");
const { getPriceSig } = require("../helpers/getPriceSig.js");
const { time } = require("@nomicfoundation/hardhat-network-helpers");
const chance = new Chance();

const nTests = 50;
const nLoans = 5;

describe("Sell fuzzing", function () {
  load.loadTest(false);

  before(async function () {
    // Create a lending pool
    const tx = await lendingMarket.createLendingPool(
      testNFT.address,
      wethAddress
    );
    await tx.wait();
    // Get the lending pool address
    lendingPoolAddress = await lendingMarket.getLendingPool(
      testNFT.address,
      wethAddress
    );
    // Get the lending pool
    lendingPool = await ethers.getContractAt("LendingPool", lendingPoolAddress);
    // Deposit ETH into the lending pool
    const depositTx = await wethGateway.depositLendingPool(
      await lendingMarket.getLendingPool(testNFT.address, weth.address),
      { value: "1000000000000000000" } // 1 ETH
    );
    await depositTx.wait();

    priceSigArray = [];
    for (var j = 0; j < nLoans; j++) {
      const mintNFTTx = await testNFT.mint(owner.address);
      await mintNFTTx.wait();

      // Approve the lending pool to take the NFT
      const approveTx = await testNFT.approve(lendingMarket.address, j);
      await approveTx.wait();

      // Get the price signature for the NFT
      const priceSig = getPriceSig(
        testNFT.address,
        [j],
        "800000",
        (await time.latest()) + 3600,
        nftOracle.address
      );
      priceSigArray.push(priceSig);
    }

    // Create a lending pool and initialize variables, etc...
    // Take a snapshot before the tests start
    snapshotId = await ethers.provider.send("evm_snapshot", []);
  });

  beforeEach(async function () {
    // Restore the blockchain state to the snapshot before each test
    await ethers.provider.send("evm_revert", [snapshotId]);

    // Take a snapshot before the tests start
    snapshotId = await ethers.provider.send("evm_snapshot", []);
  });

  for (let i = 0; i < nTests; i++) {
    it(`Fuzz test iteration ${i}`, async function () {
      const loanAmounts = Array.from({ length: nLoans }, () =>
        chance.natural({
          min: 1,
          max: 10000,
        })
      );
      const borrowRates = [];
      const creationTimes = [];

      // Time between the loan being taken and the interest being checked
      // 1 day to 1000 days
      const timeIncrease = chance.integer({
        min: 3600 * 24,
        max: 3600 * 24 * 1000,
      });

      for (var j = 0; j < nLoans; j++) {
        // Save the borrow rate before the loan
        const borrowRate = await lendingPool.getBorrowRate();
        borrowRates.push(borrowRate);

        // Borrow wETH using the NFT as collateral
        const borrowTx = await lendingMarket.borrow(
          owner.address,
          weth.address,
          loanAmounts[j],
          testNFT.address,
          [j],
          0,
          priceSigArray[j].request,
          priceSigArray[j]
        );
        await borrowTx.wait();

        // Save the creation time of the loan
        const creationTime = await time.latest();
        creationTimes.push(creationTime);
      }

      // Advance the blockchain by the time between the loan being taken and the interest being checked
      await time.increase(timeIncrease);

      // Check the interest accrued on each loan
      for (let j = 0; j < nLoans; j++) {
        const interestAccrued = await loanCenter.getLoanInterest(j);
        const loanInterestTimestamp = await time.latest();
        // Calculate the expected interest based on the borrow rate and the time elapsed
        // Interest is calculated every 30 minutes
        const loanInterestTimestampRounded = roundToNextHalfHour(
          loanInterestTimestamp
        );
        const expectedInterest = BigNumber.from(loanAmounts[j])
          .mul(borrowRates[j])
          .mul(loanInterestTimestampRounded - creationTimes[j])
          .div(10000)
          .div(3600 * 24 * 365);
        expect(interestAccrued).to.equal(expectedInterest);
      }
    });
  }
});

// Rounds a time in seconds to the nearest half hour
function roundToNextHalfHour(timeInSeconds) {
  const halfHourInSeconds = 30 * 60;
  return (
    (Math.floor((timeInSeconds - 1) / halfHourInSeconds) + 1) *
    halfHourInSeconds
  );
}
