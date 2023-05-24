const { expect } = require("chai");
const { time } = require("@nomicfoundation/hardhat-network-helpers");
const { ethers } = require("hardhat");
const load = require("../helpers/_loadTest.js");

describe("Bribes", function () {
  load.loadTest(false);

  // SHould create a new (trading) gauge and add it to the market so we can bribe it
  before(async () => {
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
    tradingGauge = await TradingGauge.deploy(
      addressProvider.address,
      tradingPool.address
    );
    await tradingGauge.deployed();

    // Add both the trading gauge to the gauge controller
    const addGaugeTx = await gaugeController.addGauge(tradingGauge.address);
    await addGaugeTx.wait();

    // Take a snapshot before the tests start
    snapshotId = await ethers.provider.send("evm_snapshot", []);
  });

  beforeEach(async function () {
    // Restore the blockchain state to the snapshot before each test
    await ethers.provider.send("evm_revert", [snapshotId]);

    // Take a snapshot before the tests start
    snapshotId = await ethers.provider.send("evm_snapshot", []);
  });

  it("Should deposit a bribe", async function () {
    // Should mint weth to the user and approve the bribes contract to spend it
    const depositWETHTx = await weth.deposit({
      value: ethers.utils.parseEther("1"),
    });
    await depositWETHTx.wait();
    const approveTx = await weth.approve(
      bribes.address,
      ethers.utils.parseEther("1")
    );
    await approveTx.wait();

    const epoch = (await votingEscrow.getEpoch(await time.latest())).toNumber();

    // Owner should have 0 balance in bribes
    expect(
      await bribes.getUserBribes(
        weth.address,
        tradingGauge.address,
        epoch + 1,
        owner.address
      )
    ).to.equal(0);

    // Should deposit the bribe
    const depositBribeTx = await bribes.depositBribe(
      owner.address,
      weth.address,
      tradingGauge.address,
      ethers.utils.parseEther("1")
    );
    await depositBribeTx.wait();

    // Owner should have 1 bribe in bribes
    expect(
      await bribes.getUserBribes(
        weth.address,
        tradingGauge.address,
        epoch + 1,
        owner.address
      )
    ).to.equal(ethers.utils.parseEther("1"));
  });
  it("Should withdraw a bribe", async function () {
    // Should mint weth to the user and approve the bribes contract to spend it
    const depositWETHTx = await weth.deposit({
      value: ethers.utils.parseEther("1"),
    });
    await depositWETHTx.wait();
    const approveTx = await weth.approve(
      bribes.address,
      ethers.utils.parseEther("1")
    );
    await approveTx.wait();

    // Should deposit the bribe
    const depositBribeTx = await bribes.depositBribe(
      owner.address,
      weth.address,
      tradingGauge.address,
      ethers.utils.parseEther("1")
    );
    await depositBribeTx.wait();

    const withdrawBribeTx = await bribes.withdrawBribe(
      owner.address,
      weth.address,
      tradingGauge.address,
      ethers.utils.parseEther("1")
    );
    await withdrawBribeTx.wait();

    // Owner should have 0 bribe in bribes
    expect(
      await bribes.getUserBribes(
        weth.address,
        tradingGauge.address,
        (await votingEscrow.getEpoch(await time.latest())).toNumber() + 1,
        owner.address
      )
    ).to.equal(0);
  });
  it("Should salvage bribes", async function () {
    // Should mint weth to the user and approve the bribes contract to spend it
    const depositWETHTx = await weth.deposit({
      value: ethers.utils.parseEther("1"),
    });
    await depositWETHTx.wait();
    const approveTx = await weth.approve(
      bribes.address,
      ethers.utils.parseEther("1")
    );
    await approveTx.wait();

    // Should deposit the bribe
    const depositBribeTx = await bribes.depositBribe(
      owner.address,
      weth.address,
      tradingGauge.address,
      ethers.utils.parseEther("1")
    );
    await depositBribeTx.wait();

    // Expect an error when trying to salvage a bribe for an epoch that hasn't started yet
    await expect(
      bribes.salvageBribes(
        weth.address,
        tradingGauge.address,
        (await votingEscrow.getEpoch(await time.latest())).toNumber() + 1
      )
    ).to.be.revertedWith("B:FUTURE_EPOCH");

    // Fast forward to the next epoch
    await time.increase(await votingEscrow.getEpochPeriod());

    // SHould have 0 balance
    expect(await weth.balanceOf(owner.address)).to.equal(0);

    // Should salvage the bribes
    const salvageBribesTx = await bribes.salvageBribes(
      weth.address,
      tradingGauge.address,
      (await votingEscrow.getEpoch(await time.latest())).toNumber()
    );
    await salvageBribesTx.wait();

    // Should have 1 weth
    expect(await weth.balanceOf(owner.address)).to.equal(
      ethers.utils.parseEther("1")
    );
  });
  it("Should claim bribes", async function () {
    // Should mint weth to the user and approve the bribes contract to spend it
    const depositWETHTx = await weth.deposit({
      value: ethers.utils.parseEther("1"),
    });
    await depositWETHTx.wait();
    const approveTx = await weth.approve(
      bribes.address,
      ethers.utils.parseEther("1")
    );
    await approveTx.wait();

    // Should deposit the bribe
    const depositBribeTx = await bribes.depositBribe(
      owner.address,
      weth.address,
      tradingGauge.address,
      ethers.utils.parseEther("1")
    );
    await depositBribeTx.wait();

    // Mint LE to create a lock and vote for the bribed gauge
    const approveNativeTokenTx = await nativeToken.approve(
      votingEscrow.address,
      ethers.utils.parseEther("1")
    );
    await approveNativeTokenTx.wait();
    const createLockTx = await votingEscrow.createLock(
      owner.address,
      ethers.utils.parseEther("1"),
      Math.floor(Date.now() / 1000) + 86400 * 100
    );
    await createLockTx.wait();
    const voteTx = await gaugeController.vote(0, tradingGauge.address, 10000);
    await voteTx.wait();

    // Fast forward to the next epoch
    await time.increase(await votingEscrow.getEpochPeriod());

    // Should have 0 balance
    expect(await weth.balanceOf(owner.address)).to.equal(0);

    // Should claim the bribes
    const claimBribesTx = await bribes.claim(
      weth.address,
      tradingGauge.address,
      0
    );
    await claimBribesTx.wait();

    // Should have 1 weth
    expect(await weth.balanceOf(owner.address)).to.equal(
      ethers.utils.parseEther("1")
    );
  });
});
