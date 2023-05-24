const { expect } = require("chai");
const { ethers } = require("hardhat");
const { BigNumber } = require("ethers");
const load = require("../helpers/_loadTest.js");
const { getPriceSig } = require("../helpers/getPriceSig.js");
const { time } = require("@nomicfoundation/hardhat-network-helpers");

describe("Locking & Gauge Rewards", function () {
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

  it("Gauge should get all the rewards if it's the only one being voted for", async function () {
    // Create a new trading pool through the market
    const createTx = await tradingPoolFactory.createTradingPool(
      testNFT.address,
      wethAddress
    );
    await createTx.wait();
    const tradingPoolAddress = await tradingPoolFactory.getTradingPool(
      testNFT.address,
      wethAddress
    );
    tradingPool = await ethers.getContractAt("TradingPool", tradingPoolAddress);
    // Create a new trading gauge and add it to the gauge controller
    const TradingGauge = await ethers.getContractFactory("TradingGauge");
    const tradingGauge = await TradingGauge.deploy(
      addressProvider.address,
      tradingPool.address
    );
    await tradingGauge.deployed();
    // Add both the trading gauge to the gauge controller
    const addGaugeTx = await gaugeController.addGauge(tradingGauge.address);
    await addGaugeTx.wait();
    const depositWETHTx = await weth.deposit({
      value: ethers.utils.parseEther("1"),
    });
    await depositWETHTx.wait();

    // Approve the trading pool to spend the weth
    const approveTx2 = await weth.approve(
      tradingPool.address,
      ethers.utils.parseEther("1")
    );
    await approveTx2.wait();
    // Mint a new NFT
    const mintTx2 = await testNFT.mint(owner.address);
    await mintTx2.wait();
    // Approve the trading pool to spend the NFT
    const approveNFTTx = await testNFT.approve(tradingPool.address, 0);
    await approveNFTTx.wait();
    // Add liquidity to the trading pool
    const depositTx = await tradingPool.addLiquidity(
      owner.address,
      0,
      [0],
      ethers.utils.parseEther("1"),
      ethers.utils.parseEther("0.5"),
      exponentialCurve.address,
      "50",
      "500"
    );
    await depositTx.wait();

    // Approve the trading gauge to spend the trading pool NFTs
    const approveTradingGaugeTx = await tradingPool.approve(
      tradingGauge.address,
      0
    );
    await approveTradingGaugeTx.wait();

    // Deposit into the trading gauge
    const depositTradingGaugeTx = await tradingGauge.deposit(0);
    await depositTradingGaugeTx.wait();

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

    // Vote for the gauge with 100 % of the voting power of the lock
    const voteTx = await gaugeController.vote(0, tradingGauge.address, 10000);
    await voteTx.wait();

    // Advange 2 epochs
    const epochPeriod = await votingEscrow.getEpochPeriod();
    await time.increase(2 * epochPeriod.toNumber());

    // Get all the epoch rewards for epoch
    const gaugeRewards = await gaugeController.callStatic.getGaugeRewards(
      tradingGauge.address,
      (await votingEscrow.getEpoch(await time.latest())).toNumber() - 1
    );
    console.log("Gauge Rewards", gaugeRewards.toString());
    const claimableRewards = await tradingGauge.callStatic.claim();
    console.log("Claimable Rewards", claimableRewards.toString());
    const userMaturityMultiplier = await tradingGauge.getUserMaturityMultiplier(
      owner.address
    );
    console.log("User Maturity Multiplier", userMaturityMultiplier.toString());

    // Should be able to claim all the rewards for the epoch (multiplied by the time factor)
    expect(claimableRewards).to.be.equal(
      BigNumber.from(gaugeRewards).mul(userMaturityMultiplier).div(10000)
    );
  });
  it("2 Gauges should share rewards in a pro rata vote weight basis", async function () {
    // Create a new trading pool through the market
    const createTx = await tradingPoolFactory.createTradingPool(
      testNFT.address,
      wethAddress
    );
    await createTx.wait();
    const tradingPoolAddress = await tradingPoolFactory.getTradingPool(
      testNFT.address,
      wethAddress
    );
    tradingPool = await ethers.getContractAt("TradingPool", tradingPoolAddress);
    // Create a new trading gauge and add it to the gauge controller
    const TradingGauge = await ethers.getContractFactory("TradingGauge");
    const tradingGauge = await TradingGauge.deploy(
      addressProvider.address,
      tradingPool.address
    );
    await tradingGauge.deployed();
    // Add both the trading gauge to the gauge controller
    const addGaugeTx = await gaugeController.addGauge(tradingGauge.address);
    await addGaugeTx.wait();
    const depositWETHTx = await weth.deposit({
      value: ethers.utils.parseEther("1"),
    });
    await depositWETHTx.wait();

    // Approve the trading pool to spend the weth
    const approveTx2 = await weth.approve(
      tradingPool.address,
      ethers.utils.parseEther("1")
    );
    await approveTx2.wait();
    // Mint a new NFT
    const mintTx2 = await testNFT.mint(owner.address);
    await mintTx2.wait();
    // Approve the trading pool to spend the NFT
    const approveNFTTx = await testNFT.approve(tradingPool.address, 0);
    await approveNFTTx.wait();
    // Add liquidity to the trading pool
    const depositTx = await tradingPool.addLiquidity(
      owner.address,
      0,
      [0],
      ethers.utils.parseEther("1"),
      ethers.utils.parseEther("0.5"),
      exponentialCurve.address,
      "50",
      "500"
    );
    await depositTx.wait();

    // Approve the trading gauge to spend the trading pool NFTs
    const approveTradingGaugeTx = await tradingPool.approve(
      tradingGauge.address,
      0
    );
    await approveTradingGaugeTx.wait();

    // Deposit into the trading gauge
    const depositTradingGaugeTx = await tradingGauge.deposit(0);
    await depositTradingGaugeTx.wait();

    // Create a new lending pool through the market
    const createTx2 = await lendingMarket.createLendingPool(
      testNFT.address,
      wethAddress
    );
    await createTx2.wait();
    const lendingPoolAddress = await lendingMarket.getLendingPool(
      testNFT.address,
      wethAddress
    );
    lendingPool = await ethers.getContractAt("LendingPool", lendingPoolAddress);
    // Create a new lending gauge and add it to the gauge controller
    const LendingGauge = await ethers.getContractFactory("LendingGauge");
    lendingGauge = await LendingGauge.deploy(
      addressProvider.address,
      lendingPool.address
    );
    await lendingGauge.deployed();

    // Add both the lening gauge to the gauge controller
    const addLendingGaugeTx = await gaugeController.addGauge(
      lendingGauge.address
    );
    await addLendingGaugeTx.wait();

    // Deposit into the lending pool
    const depositWETHTx2 = await weth.deposit({
      value: ethers.utils.parseEther("1"),
    });
    await depositWETHTx2.wait();

    // Approve the lending pool to spend the weth
    const approveTx3 = await weth.approve(
      lendingPool.address,
      ethers.utils.parseEther("1")
    );
    await approveTx3.wait();
    // Deposit into the pool
    const depositLendingPoolTx = await lendingPool.deposit(
      ethers.utils.parseEther("1"),
      owner.address
    );
    await depositLendingPoolTx.wait();

    // Approve the lending gauge to spend the lending pool tokens
    const approveLendingGaugeTx = await lendingPool.approve(
      lendingGauge.address,
      ethers.utils.parseEther("1")
    );
    await approveLendingGaugeTx.wait();

    // Deposit into the lending gauge
    const depositLendingGaugeTx = await lendingGauge.deposit(
      ethers.utils.parseEther("1")
    );
    await depositLendingGaugeTx.wait();

    // Create two lock with the LE
    const approveTx = await nativeToken.approve(
      votingEscrow.address,
      ethers.utils.parseEther("20000")
    );
    await approveTx.wait();

    const lockTx = await votingEscrow.createLock(
      owner.address,
      ethers.utils.parseEther("10000"),
      Math.floor(Date.now() / 1000) + 3600 * 24 * 30 // 30 days
    );
    await lockTx.wait();
    const lockTx2 = await votingEscrow.createLock(
      owner.address,
      ethers.utils.parseEther("10000"),
      Math.floor(Date.now() / 1000) + 3600 * 24 * 30 // 30 days
    );
    await lockTx2.wait();

    // Vote for the gauge with 100 % of the voting power of the lock
    const voteTx = await gaugeController.vote(0, tradingGauge.address, 10000);
    await voteTx.wait();

    // Vote with the other lock and 100% of its voting power in the lending gauge
    const voteTx2 = await gaugeController.vote(1, lendingGauge.address, 10000);
    await voteTx2.wait();

    // Advance 2 epochs
    const epochPeriod = await votingEscrow.getEpochPeriod();
    await time.increase(2 * epochPeriod.toNumber());

    const previousEpoch =
      (await votingEscrow.getEpoch(await time.latest())).toNumber() - 1;

    // Get all the epoch rewards for epoch 1
    const tradingGaugeRewards =
      await gaugeController.callStatic.getGaugeRewards(
        tradingGauge.address,
        previousEpoch
      );
    const lendingGaugeRewards =
      await gaugeController.callStatic.getGaugeRewards(
        lendingGauge.address,
        previousEpoch
      );
    const epochRewards = await gaugeController.callStatic.getEpochRewards(
      previousEpoch
    );
    console.log("Epoch Rewards", epochRewards.toString());
    console.log("Trading Gauge Rewards", tradingGaugeRewards.toString());
    console.log("Lending Gauge Rewards", lendingGaugeRewards.toString());

    const tradingClaimableRewards = await tradingGauge.callStatic.claim();
    console.log("Trading laimable Rewards", tradingClaimableRewards.toString());
    const lendingClaimableRewards = await lendingGauge.callStatic.claim();
    console.log("Lending laimable Rewards", lendingClaimableRewards.toString());
    const userTradingMaturityMultiplier =
      await tradingGauge.getUserMaturityMultiplier(owner.address);
    console.log(
      "User Trading Maturity Multiplier",
      userTradingMaturityMultiplier.toString()
    );
    const userLendingMaturityMultiplier =
      await lendingGauge.getUserMaturityMultiplier(owner.address);
    console.log(
      "User Lending Maturity Multiplier",
      userLendingMaturityMultiplier.toString()
    );

    // THe trading and lending gauges should have the same rewards (half the epoch rewards)
    expect(tradingGaugeRewards).to.be.equal(lendingGaugeRewards);

    // Should be able to claim all the rewards for the epoch (multiplied by the time factor)
    expect(tradingClaimableRewards).to.be.equal(
      BigNumber.from(tradingGaugeRewards)
        .mul(userTradingMaturityMultiplier)
        .div(10000)
    );
    expect(lendingClaimableRewards).to.be.equal(
      BigNumber.from(lendingGaugeRewards)
        .mul(userLendingMaturityMultiplier)
        .div(10000)
    );
  });
});
