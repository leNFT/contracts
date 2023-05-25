const { ethers } = require("hardhat");
const { BigNumber } = require("ethers");
const { expect } = require("chai");
const load = require("../helpers/_loadTest.js");
const Chance = require("chance");
const { getPriceSig } = require("../helpers/getPriceSig.js");
const { time } = require("@nomicfoundation/hardhat-network-helpers");
const chance = new Chance();

const nTests = 100;

describe("Lock fuzzing", function () {
  load.loadTest(false);

  before(async function () {
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
      const lockTime = chance.integer({
        min: 3600 * 24 * 1,
        max: 3600 * 24 * 365 * 5,
      });
      const unlockTime = Math.floor(Date.now() / 1000) + lockTime;
      const epochPeriod = await votingEscrow.getEpochPeriod();
      const roundedUnlocktime =
        Math.floor(unlockTime / epochPeriod) * epochPeriod;
      const amount = chance.integer({ min: 100, max: 5000 });

      // Create a lock with the LE
      const approveTx = await nativeToken.approve(votingEscrow.address, amount);
      await approveTx.wait();
      const lockPromise = votingEscrow.createLock(
        owner.address,
        amount,
        unlockTime
      );

      // GEt the last timestamp
      const timestamp = await time.latest();

      if (roundedUnlocktime > 4 * 52 * 7 * 24 * 3600 + timestamp) {
        console.log("Lock time too high");
        await expect(lockPromise).to.be.revertedWith("VE:CL:LOCKTIME_TOO_HIGH");
      } else if (roundedUnlocktime < 2 * 7 * 24 * 3600 + timestamp) {
        console.log("Lock time too low");
        await expect(lockPromise).to.be.revertedWith("VE:CL:LOCKTIME_TOO_LOW");
      } else {
        await expect(lockPromise).to.not.be.reverted;
        const lock = await votingEscrow.getLock(0);
        expect(lock.amount).to.equal(amount);
        expect(lock.end).to.equal(
          Math.floor(unlockTime / epochPeriod) * epochPeriod
        );
      }
    });
  }
});
