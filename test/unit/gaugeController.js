const { expect } = require("chai");
const load = require("../helpers/_loadTest.js");
const { ethers } = require("hardhat");
const { BigNumber } = require("ethers");
const { time } = require("@nomicfoundation/hardhat-network-helpers");

describe("GaugeController", () => {
  load.loadTest(false);

  // Deploy one trading pool and one lending pool and their gauges
  before(async function () {
    // Create a new trading pool
    const createTradingPoolTx = await tradingPoolFactory.createTradingPool(
      testNFT.address,
      weth.address
    );
    createTradingPoolTx.wait();

    tradingPool = await ethers.getContractAt(
      "TradingPool",
      await tradingPoolFactory.getTradingPool(testNFT.address, weth.address)
    );

    // Create a new lending pool through the market
    const createTx = await lendingMarket.createLendingPool(
      testNFT.address,
      wethAddress
    );
    await createTx.wait();
    const lendingPoolAddress = await lendingMarket.getLendingPool(
      testNFT.address,
      wethAddress
    );
    lendingPool = await ethers.getContractAt("LendingPool", lendingPoolAddress);

    // Deploy a trading gauge
    const TradingGauge = await ethers.getContractFactory("TradingGauge");
    tradingGauge = await TradingGauge.deploy(
      addressProvider.address,
      tradingPool.address
    );
    await tradingGauge.deployed();

    // Deploy a lending gauge
    const LendingGauge = await ethers.getContractFactory("LendingGauge");
    lendingGauge = await LendingGauge.deploy(
      addressProvider.address,
      lendingPool.address
    );
    await lendingGauge.deployed();

    // Take a snapshot before the tests start
    snapshotId = await ethers.provider.send("evm_snapshot", []);
  });

  beforeEach(async function () {
    // Restore the blockchain state to the snapshot before each test
    await ethers.provider.send("evm_revert", [snapshotId]);

    // Take a snapshot before the tests start
    snapshotId = await ethers.provider.send("evm_snapshot", []);
  });

  it("Should be able to add a gauge", async function () {
    // Add a trading gauge
    expect(await gaugeController.isGauge(tradingGauge.address)).to.be.false;
    const addTradingGaugeTx = await gaugeController.addGauge(
      tradingGauge.address
    );
    await addTradingGaugeTx.wait();
    expect(await gaugeController.isGauge(tradingGauge.address)).to.be.true;

    expect(await gaugeController.getGauge(tradingPool.address)).to.equal(
      tradingGauge.address
    );

    // Add a lending gauge
    expect(await gaugeController.isGauge(lendingGauge.address)).to.be.false;
    const addLendingGaugeTx = await gaugeController.addGauge(
      lendingGauge.address
    );
    await addLendingGaugeTx.wait();
    expect(await gaugeController.getGauge(lendingPool.address)).to.equal(
      lendingGauge.address
    );
  });
  it("Should be able to remove a gauge", async function () {
    // Add a trading gauge
    const addTradingGaugeTx = await gaugeController.addGauge(
      tradingGauge.address
    );
    await addTradingGaugeTx.wait();
    expect(await gaugeController.isGauge(tradingGauge.address)).to.be.true;

    expect(await gaugeController.getGauge(tradingPool.address)).to.equal(
      tradingGauge.address
    );

    // Remove a trading gauge
    const removeGaugeTx = await gaugeController.removeGauge(
      tradingGauge.address
    );
    await removeGaugeTx.wait();

    expect(await gaugeController.isGauge(tradingGauge.address)).to.be.false;

    expect(await gaugeController.getGauge(tradingPool.address)).to.equal(
      ethers.constants.AddressZero
    );
  });
  it("Should get the rewards for an epoch", async function () {
    const epochRewardCeiling = await gaugeController.getRewardsCeiling(1);
    expect(epochRewardCeiling).to.equal("11666666666666666666");
  });
  it("Should get the current gauge weight", async function () {
    // Create a lock with the LE
    const approveTx = await nativeToken.approve(
      votingEscrow.address,
      ethers.utils.parseEther("1000000")
    );
    await approveTx.wait();
    const lockTx = await votingEscrow.createLock(
      owner.address,
      ethers.utils.parseEther("1000000"),
      Math.floor(Date.now() / 1000) + 3600 * 24 * 30 // 30 days
    );
    await lockTx.wait();
    // Add a trading gauge
    const addTradingGaugeTx = await gaugeController.addGauge(
      tradingGauge.address
    );
    await addTradingGaugeTx.wait();

    // Get gauge weight (should be 0)
    expect(await gaugeController.getGaugeWeight(tradingGauge.address)).to.equal(
      0
    );

    // Vote for the gauge with 100 % of the voting power of the lock
    const voteTx = await gaugeController.vote(0, tradingGauge.address, 10000);
    await voteTx.wait();

    // Get the gauge weight
    const gaugeWeight = await gaugeController.getGaugeWeight(
      tradingGauge.address
    );
    expect(gaugeWeight).to.equal(
      BigNumber.from(await votingEscrow.getLockWeight(0))
    );
  });
  it("Should get the gauge weight at an epoch", async function () {
    // Create a lock with the LE
    const approveTx = await nativeToken.approve(
      votingEscrow.address,
      ethers.utils.parseEther("1000000")
    );
    await approveTx.wait();
    const lockTx = await votingEscrow.createLock(
      owner.address,
      ethers.utils.parseEther("1000000"),
      Math.floor(Date.now() / 1000) + 3600 * 24 * 30 // 30 days
    );
    await lockTx.wait();
    // Add a trading gauge
    const addTradingGaugeTx = await gaugeController.addGauge(
      tradingGauge.address
    );
    await addTradingGaugeTx.wait();
    // Vote for the gauge with 100 % of the voting power of the lock
    const voteTx = await gaugeController.vote(0, tradingGauge.address, 10000);
    await voteTx.wait();
    // Get the epoch period
    const epochPeriod = await votingEscrow.getEpochPeriod();

    // INcrease the block time by the 1 epoch periods
    await time.increase(epochPeriod.toNumber());
    const epoch = await votingEscrow.getEpoch(await time.latest());

    // Get the gauge weight at epoch
    const gaugeWeight = await gaugeController.callStatic.getGaugeWeightAt(
      tradingGauge.address,
      epoch
    );
    // Use the point to calculate the weight of the user at the time of the nextblock (which will be the same as the total weight)
    const lockHistoryPoint = await votingEscrow.getLockHistoryPoint(0, 0);
    const epochTimestamp = await votingEscrow.getEpochTimestamp(epoch);
    const userEpochWeight = lockHistoryPoint.bias.sub(
      lockHistoryPoint.slope.mul(epochTimestamp.sub(lockHistoryPoint.timestamp))
    );

    expect(gaugeWeight).to.equal(userEpochWeight);
  });
  it("Should vote for a gauge", async function () {
    // Create a lock with the LE
    const approveTx = await nativeToken.approve(
      votingEscrow.address,
      ethers.utils.parseEther("1000000")
    );
    await approveTx.wait();
    const lockTx = await votingEscrow.createLock(
      owner.address,
      ethers.utils.parseEther("1000000"),
      Math.floor(Date.now() / 1000) + 3600 * 24 * 30 // 30 days
    );
    await lockTx.wait();
    // Add a trading gauge
    const addTradingGaugeTx = await gaugeController.addGauge(
      tradingGauge.address
    );
    await addTradingGaugeTx.wait();

    // Vote for the gauge with 100 % of the voting power of the lock
    const voteTx = await gaugeController.vote(0, tradingGauge.address, 10000);
    await voteTx.wait();

    // The gauge weight should be 50 % of the lock weight
    expect(await gaugeController.getGaugeWeight(tradingGauge.address)).to.equal(
      BigNumber.from(await votingEscrow.getLockWeight(0))
    );

    // Thhe total weight should be 100 % of the lock weight
    expect(await gaugeController.getTotalWeight()).to.equal(
      BigNumber.from(await votingEscrow.getLockWeight(0))
    );

    // the vote lock ratio should be 100 %
    expect(await gaugeController.getLockVoteRatio(0)).to.equal(10000);

    // the lock vote ratio for the gauge should be 100 %
    expect(
      await gaugeController.getLockVoteRatioForGauge(0, tradingGauge.address)
    ).to.equal(10000);

    // the lock vote weight for the gauge should be 10000 of the lock weight
    expect(
      await gaugeController.getLockVoteWeightForGauge(0, tradingGauge.address)
    ).to.equal(BigNumber.from(await votingEscrow.getLockWeight(0)));
  });
  it("Should set the lp maturity period", async function () {
    const newLPMaturityPeriod = 8;
    const setLPMaturityPeriodTx = await gaugeController.setLPMaturityPeriod(
      newLPMaturityPeriod
    );
    await setLPMaturityPeriodTx.wait();

    expect(await gaugeController.getLPMaturityPeriod()).to.equal(
      newLPMaturityPeriod
    );
  });
  it("Should get the rewards for a certain epoch", async function () {
    // Create a lock with the LE
    const approveTx = await nativeToken.approve(
      votingEscrow.address,
      ethers.utils.parseEther("1000000")
    );
    await approveTx.wait();
    const lockTx = await votingEscrow.createLock(
      owner.address,
      ethers.utils.parseEther("1000000"),
      Math.floor(Date.now() / 1000) + 3600 * 24 * 30 // 30 days
    );
    await lockTx.wait();
    // Add a trading gauge
    const addTradingGaugeTx = await gaugeController.addGauge(
      tradingGauge.address
    );
    await addTradingGaugeTx.wait();
    // Vote for the gauge with 50 % of the voting power of the lock
    const voteTx = await gaugeController.vote(0, tradingGauge.address, 5000);
    await voteTx.wait();

    // Get the epoch period
    const epochPeriod = await votingEscrow.getEpochPeriod();
    console.log(epochPeriod.toNumber());
    // INcrease the block time by 2x the epoch period
    await time.increase(2 * epochPeriod.toNumber());

    const epoch = await votingEscrow.getEpoch(await time.latest());

    // Get the rewards for the epoch
    expect(
      await gaugeController.callStatic.getEpochRewards(epoch - 2)
    ).to.equal("0");

    // Get the rewards for the epoch 1
    expect(await gaugeController.callStatic.getEpochRewards(epoch)).to.equal(
      "32941720000000000000"
    );
  });
  it("Should get the gauge rewards for a certain epoch", async function () {
    // Create a lock with the LE
    const approveTx = await nativeToken.approve(
      votingEscrow.address,
      ethers.utils.parseEther("1000000")
    );
    await approveTx.wait();
    const lockTx = await votingEscrow.createLock(
      owner.address,
      ethers.utils.parseEther("1000000"),
      Math.floor(Date.now() / 1000) + 3600 * 24 * 30 // 30 days
    );
    await lockTx.wait();

    // Add a trading gauge
    const addTradingGaugeTx = await gaugeController.addGauge(
      tradingGauge.address
    );
    await addTradingGaugeTx.wait();

    // Vote for the gauge with 50 % of the voting power of the lock
    const voteTx = await gaugeController.vote(0, tradingGauge.address, 5000);
    await voteTx.wait();

    // Get the epoch period
    const epochPeriod = await votingEscrow.getEpochPeriod();
    console.log(epochPeriod.toNumber());
    // INcrease the block time by the epoch period
    await time.increase(2 * epochPeriod.toNumber());

    // Get the rewards for the epoch 1
    expect(
      await gaugeController.callStatic.getGaugeRewards(tradingGauge.address, 1)
    ).to.equal(await gaugeController.callStatic.getEpochRewards(1));
  });
});
