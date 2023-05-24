const { expect } = require("chai");
const load = require("../helpers/_loadTest.js");
const { ethers } = require("hardhat");
const { time } = require("@nomicfoundation/hardhat-network-helpers");
const { isValidJSON, isValidSVG } = require("../helpers/validateFormats.js");
const { BigNumber } = require("ethers");

describe("VotingEscrow", () => {
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

  it("Should get the current epoch", async function () {
    const epochPeriod = await votingEscrow.getEpochPeriod();
    const currentTime = await time.latest();
    expect(await votingEscrow.getEpoch(currentTime)).to.equal(1);

    // Test the first 10 epochs
    var nextTime;
    for (let i = 1; i < 10; i++) {
      await time.increase(epochPeriod);
      nextTime = await time.latest();
      expect(await votingEscrow.getEpoch(nextTime)).to.equal(i + 1);
    }
  });
  it("Should get the correct epoch timstamp", async function () {
    const epochPeriod = await votingEscrow.getEpochPeriod();

    const epoch0Timestamp = await votingEscrow.getEpochTimestamp(0);

    // Test the first 10 epochs
    for (let i = 0; i < 10; i++) {
      expect(await votingEscrow.getEpochTimestamp(i + 1)).to.equal(
        epoch0Timestamp.add(epochPeriod.mul(i + 1))
      );
    }
  });
  it("Should get the correct JSON token URI", async function () {
    // Create a lock with the LE
    const approveTx = await nativeToken.approve(
      votingEscrow.address,
      ethers.utils.parseEther("10000")
    );
    await approveTx.wait();
    const lockTx = await votingEscrow.createLock(
      owner.address,
      ethers.utils.parseEther("10000"),
      Math.floor(Date.now() / 1000) + 3600 * 24 * 30 // 30 days
    );
    await lockTx.wait();

    // Get the token URI
    const tokenURI = await votingEscrow.tokenURI(0);
    const base64Data = tokenURI.split("base64,")[1]; // Extract the base64 content
    console.log(base64Data);
    const decodedDataBuffer = ethers.utils.base64.decode(base64Data);
    const decodedData = Buffer.from(decodedDataBuffer).toString("utf-8"); // Convert ArrayBuffer to a UTF-8 string using Buffer.from()

    expect(isValidJSON(decodedData)).to.be.true;
  });
  it("Should get the correct SVG", async function () {
    // Create a lock with the LE
    const approveTx = await nativeToken.approve(
      votingEscrow.address,
      ethers.utils.parseEther("10000")
    );
    await approveTx.wait();
    const lockTx = await votingEscrow.createLock(
      owner.address,
      ethers.utils.parseEther("10000"),
      Math.floor(Date.now() / 1000) + 3600 * 24 * 30 // 30 days
    );
    await lockTx.wait();

    // Get the token svg
    const svg = await votingEscrow.svg(0);
    const decodedData = ethers.utils.toUtf8String(svg); // Convert the hex string to a UTF-8 string

    expect(isValidSVG(decodedData)).to.be.true;
  });
  it("Should simulate a lock's weight", async function () {
    const unlockTime = Math.floor(Date.now() / 1000) + 3600 * 24 * 30;
    console.log(unlockTime);

    // Create a lock with the LE
    const approveTx = await nativeToken.approve(
      votingEscrow.address,
      ethers.utils.parseEther("10000")
    );
    await approveTx.wait();
    const lockTx = await votingEscrow.createLock(
      owner.address,
      ethers.utils.parseEther("100"),
      unlockTime
    );
    await lockTx.wait();

    // Simulate the lock
    const simulatedLock = await votingEscrow.simulateLock(
      ethers.utils.parseEther("100"),
      unlockTime
    );

    expect(simulatedLock).closeTo(
      await votingEscrow.getLockWeight(0),
      ethers.utils.parseEther("0.000001")
    );
  });
  it("Should get the locked ratio for a certain epoch", async function () {
    const unlockTime = Math.floor(Date.now() / 1000) + 3600 * 24 * 30;
    console.log(unlockTime);

    // Create a lock with the LE
    const approveTx = await nativeToken.approve(
      votingEscrow.address,
      ethers.utils.parseEther("10000000")
    );
    await approveTx.wait();
    const lockTx = await votingEscrow.createLock(
      owner.address,
      ethers.utils.parseEther("10000000"),
      unlockTime
    );
    await lockTx.wait();

    // Increase the time to the next epoch
    const epochPeriod = await votingEscrow.getEpochPeriod();
    await time.increase(epochPeriod);

    const epoch = await votingEscrow.getEpoch(await time.latest());

    expect(await votingEscrow.callStatic.getLockedRatioAt(epoch)).to.equal(
      10000
    );

    // Increase the time to the next epoch
    await time.increase(epochPeriod);

    const nextEpoch = await votingEscrow.getEpoch(await time.latest());

    expect(await votingEscrow.callStatic.getLockedRatioAt(nextEpoch)).to.equal(
      10000
    );
  });
  it("Should get the total weight for a certain epoch", async function () {
    const unlockTime = Math.floor(Date.now() / 1000) + 3600 * 24 * 30;
    console.log(unlockTime);

    // Create a lock with the LE
    const approveTx = await nativeToken.approve(
      votingEscrow.address,
      ethers.utils.parseEther("10000")
    );
    await approveTx.wait();
    const lockTx = await votingEscrow.createLock(
      owner.address,
      ethers.utils.parseEther("10000"),
      unlockTime
    );
    await lockTx.wait();

    // Increase the time to the next epoch
    const epochPeriod = await votingEscrow.getEpochPeriod();
    await time.increase(epochPeriod);

    const epoch = await votingEscrow.getEpoch(await time.latest());

    const epochTimestamp = await votingEscrow.getEpochTimestamp(epoch);
    const lockHistoryLength = await votingEscrow.getLockHistoryLength(0);
    const lockHistoryPoint = await votingEscrow.getLockHistoryPoint(
      0,
      lockHistoryLength - 1
    );

    // Use the point to calculate the weight of the user at the epoch 1 (which will be the same as the total weight)
    const userEpochWeight = lockHistoryPoint.bias.sub(
      lockHistoryPoint.slope.mul(epochTimestamp.sub(lockHistoryPoint.timestamp))
    );

    expect(await votingEscrow.callStatic.getTotalWeightAt(epoch)).to.equal(
      userEpochWeight
    );
  });
  it("Should get the total weight", async function () {
    const unlockTime = Math.floor(Date.now() / 1000) + 3600 * 24 * 30;
    console.log(unlockTime);

    // Create a lock with the LE
    const approveTx = await nativeToken.approve(
      votingEscrow.address,
      ethers.utils.parseEther("10000")
    );
    await approveTx.wait();
    const lockTx = await votingEscrow.createLock(
      owner.address,
      ethers.utils.parseEther("10000"),
      unlockTime
    );
    await lockTx.wait();

    const lockHistoryLength = await votingEscrow.getLockHistoryLength(0);
    const lockHistoryPoint = await votingEscrow.getLockHistoryPoint(
      0,
      lockHistoryLength - 1
    );

    // Increase the time to the next epoch
    const epochPeriod = await votingEscrow.getEpochPeriod();
    await time.increase(epochPeriod);

    const nextBlockTimestamp = BigNumber.from((await time.latest()) + 10);

    // Use the point to calculate the weight of the user at the time of the nextblock (which will be the same as the total weight)
    const userNextBlockWeight = lockHistoryPoint.bias.sub(
      lockHistoryPoint.slope.mul(
        nextBlockTimestamp.sub(lockHistoryPoint.timestamp)
      )
    );

    // Set the block timestamp to the next block timestamp
    await time.increaseTo(nextBlockTimestamp);

    expect(await votingEscrow.callStatic.getTotalWeight()).to.equal(
      userNextBlockWeight
    );
  });
  it("Should get the user weight", async function () {
    const unlockTime = Math.floor(Date.now() / 1000) + 3600 * 24 * 30;
    console.log(unlockTime);

    // Create a lock with the LE
    const approveTx = await nativeToken.approve(
      votingEscrow.address,
      ethers.utils.parseEther("10000")
    );
    await approveTx.wait();
    const lockTx = await votingEscrow.createLock(
      owner.address,
      ethers.utils.parseEther("10000"),
      unlockTime
    );
    await lockTx.wait();

    const lockHistoryLength = await votingEscrow.getLockHistoryLength(0);
    const lockHistoryPoint = await votingEscrow.getLockHistoryPoint(
      0,
      lockHistoryLength - 1
    );

    // Increase the time to the next epoch
    const epochPeriod = await votingEscrow.getEpochPeriod();
    await time.increase(epochPeriod);

    const nextBlockTimestamp = BigNumber.from((await time.latest()) + 10);

    // Use the point to calculate the weight of the user at the time of the nextblock (which will be the same as the total weight)
    const userNextBlockWeight = lockHistoryPoint.bias.sub(
      lockHistoryPoint.slope.mul(
        nextBlockTimestamp.sub(lockHistoryPoint.timestamp)
      )
    );

    // Set the block timestamp to the next block timestamp
    await time.increaseTo(nextBlockTimestamp);

    expect(await votingEscrow.getUserWeight(owner.address)).to.equal(
      userNextBlockWeight
    );
  });
  it("Should get a lock's weight", async function () {
    const unlockTime = Math.floor(Date.now() / 1000) + 3600 * 24 * 30;
    console.log(unlockTime);

    // Create a lock with the LE
    const approveTx = await nativeToken.approve(
      votingEscrow.address,
      ethers.utils.parseEther("10000")
    );
    await approveTx.wait();
    const lockTx = await votingEscrow.createLock(
      owner.address,
      ethers.utils.parseEther("10000"),
      unlockTime
    );
    await lockTx.wait();

    const lockHistoryLength = await votingEscrow.getLockHistoryLength(0);
    const lockHistoryPoint = await votingEscrow.getLockHistoryPoint(
      0,
      lockHistoryLength - 1
    );

    // Increase the time to the next epoch
    const epochPeriod = await votingEscrow.getEpochPeriod();
    await time.increase(epochPeriod);

    const nextBlockTimestamp = BigNumber.from((await time.latest()) + 10);

    // Use the point to calculate the weight of the user at the time of the nextblock (which will be the same as the total weight)
    const userNextBlockWeight = lockHistoryPoint.bias.sub(
      lockHistoryPoint.slope.mul(
        nextBlockTimestamp.sub(lockHistoryPoint.timestamp)
      )
    );

    // Set the block timestamp to the next block timestamp
    await time.increaseTo(nextBlockTimestamp);

    expect(await votingEscrow.getLockWeight(0)).to.equal(userNextBlockWeight);
  });
  it("Should create a lock", async function () {
    const unlockTime = Math.floor(Date.now() / 1000) + 3600 * 24 * 30;
    console.log(unlockTime);

    // Create a lock with the LE
    const approveTx = await nativeToken.approve(
      votingEscrow.address,
      ethers.utils.parseEther("10000")
    );
    await approveTx.wait();
    const lockTx = await votingEscrow.createLock(
      owner.address,
      ethers.utils.parseEther("10000"),
      unlockTime
    );
    await lockTx.wait();

    const lock = await votingEscrow.getLock(0);
    const epochPeriod = await votingEscrow.getEpochPeriod();

    expect(lock.amount).to.equal(ethers.utils.parseEther("10000"));
    expect(lock.end).to.equal(
      Math.floor(unlockTime / epochPeriod) * epochPeriod
    );
  });
  it("Should increase the amount in a lock", async function () {
    const unlockTime = Math.floor(Date.now() / 1000) + 3600 * 24 * 30;
    console.log(unlockTime);

    // Create a lock with the LE
    const approveTx = await nativeToken.approve(
      votingEscrow.address,
      ethers.utils.parseEther("20000")
    );
    await approveTx.wait();
    const lockTx = await votingEscrow.createLock(
      owner.address,
      ethers.utils.parseEther("10000"),
      unlockTime
    );
    await lockTx.wait();

    // Should increase the amount in the lock
    const increaseAmountTx = await votingEscrow.increaseAmount(
      0,
      ethers.utils.parseEther("10000")
    );
    await increaseAmountTx.wait();

    // Should have increased the amount in the lock
    const lock = await votingEscrow.getLock(0);
    expect(lock.amount).to.equal(ethers.utils.parseEther("20000"));
  });
  it("Should increase the unlockTime in a lock", async function () {
    const unlockTime = Math.floor(Date.now() / 1000) + 3600 * 24 * 30;
    console.log(unlockTime);

    // Create a lock with the LE
    const approveTx = await nativeToken.approve(
      votingEscrow.address,
      ethers.utils.parseEther("10000")
    );
    await approveTx.wait();
    const lockTx = await votingEscrow.createLock(
      owner.address,
      ethers.utils.parseEther("10000"),
      unlockTime
    );
    await lockTx.wait();

    // Should increase the unlock time
    const increaseUnlockTimeTx = await votingEscrow.increaseUnlockTime(
      0,
      unlockTime + 3600 * 24 * 30
    );
    await increaseUnlockTimeTx.wait();

    const lock = await votingEscrow.getLock(0);
    const epochPeriod = await votingEscrow.getEpochPeriod();
    expect(lock.end).to.equal(
      Math.floor((unlockTime + 3600 * 24 * 30) / epochPeriod) * epochPeriod
    );
  });
  it("Should withdraw a lock", async function () {
    const unlockTime = Math.floor(Date.now() / 1000) + 3600 * 24 * 30;
    console.log(unlockTime);

    // Create a lock with the LE
    const approveTx = await nativeToken.approve(
      votingEscrow.address,
      ethers.utils.parseEther("10000")
    );
    await approveTx.wait();
    const lockTx = await votingEscrow.createLock(
      owner.address,
      ethers.utils.parseEther("10000"),
      unlockTime
    );
    await lockTx.wait();

    // Should increase the time
    await time.increaseTo(unlockTime + 3600 * 24 * 30);

    // Save the balance of the owner
    const balanceBefore = await nativeToken.balanceOf(owner.address);

    // Should withdraw the lock
    const withdrawTx = await votingEscrow.withdraw(0);
    await withdrawTx.wait();

    // Should throw an error when getting the lock
    await expect(votingEscrow.getLock(0)).to.be.revertedWith(
      "VE:LOCK_NOT_FOUND"
    );

    // Should have the correct balance
    expect(await nativeToken.balanceOf(owner.address)).to.equal(
      balanceBefore.add(ethers.utils.parseEther("10000"))
    );

    // Should throw an error if we try to withdraw again
    await expect(votingEscrow.withdraw(0)).to.be.revertedWith(
      "VE:LOCK_NOT_FOUND"
    );
  });
  it("Should claim rebates for a lock", async function () {
    const unlockTime = Math.floor(Date.now() / 1000) + 3600 * 24 * 30;
    console.log(unlockTime);

    // Create a lock with the LE
    const approveTx = await nativeToken.approve(
      votingEscrow.address,
      ethers.utils.parseEther("10000")
    );
    await approveTx.wait();
    const lockTx = await votingEscrow.createLock(
      owner.address,
      ethers.utils.parseEther("10000"),
      unlockTime
    );
    await lockTx.wait();

    // Create a trading gauge and vote for it
    const createTradingPoolTx = await tradingPoolFactory.createTradingPool(
      testNFT.address,
      weth.address
    );
    createTradingPoolTx.wait();
    tradingPool = await ethers.getContractAt(
      "TradingPool",
      await tradingPoolFactory.getTradingPool(testNFT.address, weth.address)
    );
    const TradingGauge = await ethers.getContractFactory("TradingGauge");
    tradingGauge = await TradingGauge.deploy(
      addressProvider.address,
      tradingPool.address
    );
    await tradingGauge.deployed();
    const addTradingGaugeTx = await gaugeController.addGauge(
      tradingGauge.address
    );
    await addTradingGaugeTx.wait();
    const voteForGaugeTx = await gaugeController.vote(
      0,
      tradingGauge.address,
      10000 // 100%
    );
    await voteForGaugeTx.wait();

    // Should increase the time by two epochs
    const epochPeriod = await votingEscrow.getEpochPeriod();
    await time.increase(2 * epochPeriod);

    // Save the balance of the owner
    const balanceBefore = await nativeToken.balanceOf(owner.address);

    // Should claim the rebates for epoch 1
    const claimTx = await votingEscrow.claimRebates(0);
    await claimTx.wait();

    // Should have the correct balance
    expect(await nativeToken.balanceOf(owner.address)).to.equal(
      balanceBefore.add("335415108764438")
    );
  });
  it("Should claim rebates for multiple locks", async function () {
    const unlockTime = Math.floor(Date.now() / 1000) + 3600 * 24 * 30;
    console.log(unlockTime);

    // Create a lock with the LE
    const approveTx = await nativeToken.approve(
      votingEscrow.address,
      ethers.utils.parseEther("20000")
    );
    await approveTx.wait();
    const lockTx = await votingEscrow.createLock(
      owner.address,
      ethers.utils.parseEther("10000"),
      unlockTime
    );
    await lockTx.wait();
    const lockTx2 = await votingEscrow.createLock(
      owner.address,
      ethers.utils.parseEther("10000"),
      unlockTime
    );
    await lockTx2.wait();

    // Create a trading gauge and vote for it
    const createTradingPoolTx = await tradingPoolFactory.createTradingPool(
      testNFT.address,
      weth.address
    );
    createTradingPoolTx.wait();
    tradingPool = await ethers.getContractAt(
      "TradingPool",
      await tradingPoolFactory.getTradingPool(testNFT.address, weth.address)
    );
    const TradingGauge = await ethers.getContractFactory("TradingGauge");
    tradingGauge = await TradingGauge.deploy(
      addressProvider.address,
      tradingPool.address
    );
    await tradingGauge.deployed();
    const addTradingGaugeTx = await gaugeController.addGauge(
      tradingGauge.address
    );
    await addTradingGaugeTx.wait();
    const voteForGaugeTx = await gaugeController.vote(
      0,
      tradingGauge.address,
      10000 // 100%
    );
    await voteForGaugeTx.wait();
    const voteForGaugeTx2 = await gaugeController.vote(
      1,
      tradingGauge.address,
      10000 // 100%
    );
    await voteForGaugeTx2.wait();

    // Should increase the time by two epochs
    const epochPeriod = await votingEscrow.getEpochPeriod();
    await time.increase(2 * epochPeriod);

    // Save the balance of the owner
    const balanceBefore = await nativeToken.balanceOf(owner.address);

    // Should claim the rebates for epoch 1
    const claimTx = await votingEscrow.claimRebatesBatch([0, 1]);
    await claimTx.wait();

    // Should have the correct balance
    expect(await nativeToken.balanceOf(owner.address)).to.equal(
      balanceBefore.add("670427719409094")
    );
  });
});
