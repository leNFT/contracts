const { expect } = require("chai");
const load = require("../helpers/_loadTest.js");
const { ethers } = require("hardhat");
const { time } = require("@nomicfoundation/hardhat-network-helpers");

describe("LendingGauge", () => {
  load.loadTest(false);

  // Create a new lending pool and its associated lending gauge
  before(async () => {
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

    // Take a snapshot before the tests start
    snapshotId = await ethers.provider.send("evm_snapshot", []);
  });

  beforeEach(async function () {
    // Restore the blockchain state to the snapshot before each test
    await ethers.provider.send("evm_revert", [snapshotId]);

    // Take a snapshot before the tests start
    snapshotId = await ethers.provider.send("evm_snapshot", []);
  });

  it("Should deposit into a lending gauge", async function () {
    // Deposit into the lending pool
    const depositWETHTx = await weth.deposit({
      value: ethers.utils.parseEther("1"),
    });
    await depositWETHTx.wait();

    // Approve the lending pool to spend the weth
    const approveTx = await weth.approve(
      lendingPool.address,
      ethers.utils.parseEther("1")
    );
    await approveTx.wait();
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

    // THe balance and token supply should be 1
    expect(await lendingGauge.getBalanceOf(owner.address)).to.equal(
      ethers.utils.parseEther("1")
    );
    expect(await lendingGauge.getTotalSupply()).to.equal(
      ethers.utils.parseEther("1")
    );
  });
  it("Should withdraw from  a lending gauge", async function () {
    // Deposit into the lending pool
    const depositWETHTx = await weth.deposit({
      value: ethers.utils.parseEther("1"),
    });
    await depositWETHTx.wait();

    // Approve the lending pool to spend the weth
    const approveTx = await weth.approve(
      lendingPool.address,
      ethers.utils.parseEther("1")
    );
    await approveTx.wait();
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

    // THe balance and token supply should be 1
    expect(await lendingGauge.getBalanceOf(owner.address)).to.equal(
      ethers.utils.parseEther("1")
    );

    // Withdraw from the lending gauge
    const withdrawLendingGaugeTx = await lendingGauge.withdraw(
      ethers.utils.parseEther("1")
    );
    await withdrawLendingGaugeTx.wait();

    // The balance and token supply should be 0
    expect(await lendingGauge.getBalanceOf(owner.address)).to.equal(
      ethers.utils.parseEther("0")
    );
    expect(await lendingGauge.getTotalSupply()).to.equal(
      ethers.utils.parseEther("0")
    );
  });
  it("Should get the user boost", async function () {
    // Deposit into the lending pool
    const depositWETHTx = await weth.deposit({
      value: ethers.utils.parseEther("1"),
    });
    await depositWETHTx.wait();

    // Approve the lending pool to spend the weth
    const approveTx = await weth.approve(
      lendingPool.address,
      ethers.utils.parseEther("1")
    );
    await approveTx.wait();
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

    expect(await lendingGauge.getUserBoost(owner.address)).to.equal(20000);
  });
  it("Should get the user maturity", async function () {
    // Deposit into the lending pool
    const depositWETHTx = await weth.deposit({
      value: ethers.utils.parseEther("1"),
    });
    await depositWETHTx.wait();

    // Approve the lending pool to spend the weth
    const approveTx = await weth.approve(
      lendingPool.address,
      ethers.utils.parseEther("1")
    );
    await approveTx.wait();
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

    // Get epoch time
    const epochPeriod = await votingEscrow.getEpochPeriod();
    // Let 3 epochs pass
    await time.increase(epochPeriod.mul(3).toNumber());

    expect(
      await lendingGauge.getUserMaturityMultiplier(owner.address)
    ).to.equal(5000);
  });
  it("Should claim rewards", async function () {
    // Deposit into the lending pool
    const depositWETHTx = await weth.deposit({
      value: ethers.utils.parseEther("1"),
    });
    await depositWETHTx.wait();

    // Approve the lending pool to spend the weth
    const approveTx = await weth.approve(
      lendingPool.address,
      ethers.utils.parseEther("1")
    );
    await approveTx.wait();
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

    // Approve the voting escrow to spend the LE tokens
    const approveVotingEscrowTx = await nativeToken.approve(
      votingEscrow.address,
      ethers.utils.parseEther("1")
    );
    await approveVotingEscrowTx.wait();

    // Vote
    const lockTx = await votingEscrow.createLock(
      owner.address,
      ethers.utils.parseEther("1"),
      Math.floor(Date.now() / 1000) + 3600 * 24 * 30 // 30 days
    );
    await lockTx.wait();

    // Vote for the gauge with 100 % of the voting power of the lock
    const voteTx = await gaugeController.vote(0, lendingGauge.address, 10000);
    await voteTx.wait();

    // Get epoch time
    const epochPeriod = await votingEscrow.getEpochPeriod();
    // Let 2 epochs pass
    await time.increase(2 * epochPeriod.toNumber());

    // Save the current balance of the user
    const balanceBefore = await nativeToken.balanceOf(owner.address);

    // Call claim rewards statically
    const rewards = await lendingGauge.callStatic.claim();

    // Claim rewards
    const claimRewardsTx = await lendingGauge.claim();
    await claimRewardsTx.wait();

    // The user should have received the rewards
    expect(await nativeToken.balanceOf(owner.address)).to.equal(
      balanceBefore.add(rewards)
    );
  });
  it("Should use kick to update the boost for a user whose lock is over", async function () {
    //  Mint and lock some LE for the user
    const approveNativeTokenTx = await nativeToken.approve(
      votingEscrow.address,
      ethers.utils.parseEther("2")
    );
    await approveNativeTokenTx.wait();
    // Create a lock for 30 days for the user
    const lockTx = await votingEscrow.createLock(
      owner.address,
      ethers.utils.parseEther("1"),
      Math.floor(Date.now() / 1000) + 3600 * 24 * 30 // 30 days
    );
    await lockTx.wait();
    // Create a lock for 120 days for the user
    const lockTx2 = await votingEscrow.createLock(
      address1.address,
      ethers.utils.parseEther("1"),
      Math.floor(Date.now() / 1000) + 3600 * 24 * 120 // 30 days
    );
    await lockTx2.wait();
    // Deposit into the lending pool
    const depositWETHTx = await weth.deposit({
      value: ethers.utils.parseEther("1"),
    });
    await depositWETHTx.wait();

    // Approve the lending pool to spend the weth
    const approveTx = await weth.approve(
      lendingPool.address,
      ethers.utils.parseEther("1")
    );
    await approveTx.wait();
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

    // Let 30 days pass
    await time.increase(3600 * 24 * 30);

    expect(Number(await lendingGauge.getUserBoost(owner.address)))
      .to.greaterThan(10000)
      .and.lessThan(20000);

    // Kick the user's lock
    const kickTx = await lendingGauge.kick(0);
    await kickTx.wait();

    // The boost should be updated
    console.log("Get user boost");
    expect(await lendingGauge.getUserBoost(owner.address)).to.equal(10000);
  });
});
