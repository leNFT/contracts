const { expect } = require("chai");
const load = require("../helpers/_loadTest.js");
const { ethers } = require("hardhat");
const { time } = require("@nomicfoundation/hardhat-network-helpers");

describe("TradingGauge", () => {
  load.loadTest(false);

  // Create a new trading pool and its associated trading gauge
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

  it("Should deposit into a trading gauge", async function () {
    const depositWETHTx = await weth.deposit({
      value: ethers.utils.parseEther("1"),
    });
    await depositWETHTx.wait();

    // Approve the trading pool to spend the weth
    const approveTx = await weth.approve(
      tradingPool.address,
      ethers.utils.parseEther("1")
    );
    await approveTx.wait();
    // Mint a new NFT
    const mintTx = await testNFT.mint(owner.address);
    await mintTx.wait();
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

    const lpValue = await tradingGauge.calculateLpValue(
      1,
      ethers.utils.parseEther("1"),
      ethers.utils.parseEther("0.5")
    );
    console.log(lpValue.toString());

    // THe user value should be the same a the lp he deposited
    expect(await tradingGauge.getUserLPValue(owner.address)).to.equal(lpValue);

    // The total value should be the same a the lp he deposited
    expect(await tradingGauge.getTotalLPValue()).to.equal(lpValue);

    // The trading gauge should own the liquidity pair NFT
    expect(await tradingPool.ownerOf(0)).to.equal(tradingGauge.address);

    // THe balance for the user should be 1
    expect(await tradingGauge.getBalanceOf(owner.address)).to.equal(1);

    expect(await tradingGauge.getLPOfOwnerByIndex(owner.address, 0)).to.equal(
      0
    );
  });
  it("Should withdraw from  a trading gauge", async function () {
    const depositWETHTx = await weth.deposit({
      value: ethers.utils.parseEther("1"),
    });
    await depositWETHTx.wait();

    // Approve the trading pool to spend the weth
    const approveTx = await weth.approve(
      tradingPool.address,
      ethers.utils.parseEther("1")
    );
    await approveTx.wait();
    // Mint a new NFT
    const mintTx = await testNFT.mint(owner.address);
    await mintTx.wait();
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

    // Withdraw from the trading gauge
    const withdrawTradingGaugeTx = await tradingGauge.withdraw(0);
    await withdrawTradingGaugeTx.wait();

    // The balance and token supply should be 0
    expect(await tradingGauge.getUserLPValue(owner.address)).to.equal(0);
    expect(await tradingGauge.getTotalSupply()).to.equal(
      ethers.utils.parseEther("0")
    );

    // The user should own the liquidity pair NFT
    expect(await tradingPool.ownerOf(0)).to.equal(owner.address);

    // THe balance for the user should be 0
    expect(await tradingGauge.getBalanceOf(owner.address)).to.equal(0);
  });
  it("Should batch withdraw from  a trading gauge", async function () {
    const depositWETHTx = await weth.deposit({
      value: ethers.utils.parseEther("2"),
    });
    await depositWETHTx.wait();

    // Approve the trading pool to spend the weth
    const approveTx = await weth.approve(
      tradingPool.address,
      ethers.utils.parseEther("2")
    );
    await approveTx.wait();
    // Mint two new NFT
    const mintTx1 = await testNFT.mint(owner.address);
    await mintTx1.wait();
    const mintTx2 = await testNFT.mint(owner.address);
    await mintTx2.wait();
    // Approve the trading pool to spend the NFT
    const approveNFTTx = await testNFT.approve(tradingPool.address, 0);
    await approveNFTTx.wait();
    const approveNFTTx2 = await testNFT.approve(tradingPool.address, 1);
    await approveNFTTx2.wait();
    // Add liquidity to the trading pool
    const depositTx1 = await tradingPool.addLiquidity(
      owner.address,
      0,
      [0],
      ethers.utils.parseEther("1"),
      ethers.utils.parseEther("0.5"),
      exponentialCurve.address,
      "50",
      "500"
    );
    await depositTx1.wait();
    const depositTx2 = await tradingPool.addLiquidity(
      owner.address,
      0,
      [1],
      ethers.utils.parseEther("1"),
      ethers.utils.parseEther("0.5"),
      exponentialCurve.address,
      "50",
      "500"
    );
    await depositTx2.wait();

    // Approve the trading gauge to spend the trading pool NFTs
    const approveTradingGaugeTx = await tradingPool.approve(
      tradingGauge.address,
      0
    );
    await approveTradingGaugeTx.wait();
    const approveTradingGaugeTx2 = await tradingPool.approve(
      tradingGauge.address,
      1
    );
    await approveTradingGaugeTx2.wait();

    // Deposit into the trading gauge
    const depositTradingGaugeTx = await tradingGauge.deposit(0);
    await depositTradingGaugeTx.wait();
    const depositTradingGaugeTx2 = await tradingGauge.deposit(1);
    await depositTradingGaugeTx2.wait();

    // Withdraw from the trading gauge in batch
    const withdrawBatchTradingGaugeTx = await tradingGauge.withdrawBatch([
      0, 1,
    ]);
    await withdrawBatchTradingGaugeTx.wait();

    // The balance and token supply should be 0
    expect(await tradingGauge.getUserLPValue(owner.address)).to.equal(0);
    expect(await tradingGauge.getTotalSupply()).to.equal(
      ethers.utils.parseEther("0")
    );

    // The user should own the liquidity pair NFTs
    expect(await tradingPool.ownerOf(0)).to.equal(owner.address);
    expect(await tradingPool.ownerOf(1)).to.equal(owner.address);

    // THe balance for the user should be 0
    expect(await tradingGauge.getBalanceOf(owner.address)).to.equal(0);
  });
  it("Should get the user boost", async function () {
    const depositWETHTx = await weth.deposit({
      value: ethers.utils.parseEther("1"),
    });
    await depositWETHTx.wait();

    // Approve the trading pool to spend the weth
    const approveTx = await weth.approve(
      tradingPool.address,
      ethers.utils.parseEther("1")
    );
    await approveTx.wait();
    // Mint a new NFT
    const mintTx = await testNFT.mint(owner.address);
    await mintTx.wait();
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

    expect(await tradingGauge.getUserBoost(owner.address)).to.equal(20000);
  });
  it("Should get the user maturity", async function () {
    const depositWETHTx = await weth.deposit({
      value: ethers.utils.parseEther("1"),
    });
    await depositWETHTx.wait();

    // Approve the trading pool to spend the weth
    const approveTx = await weth.approve(
      tradingPool.address,
      ethers.utils.parseEther("1")
    );
    await approveTx.wait();
    // Mint a new NFT
    const mintTx = await testNFT.mint(owner.address);
    await mintTx.wait();
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

    // Get epoch time
    const epochPeriod = await votingEscrow.getEpochPeriod();
    // Let 3 epochs pass
    await time.increase(epochPeriod.mul(3).toNumber());

    expect(
      await tradingGauge.getUserMaturityMultiplier(owner.address)
    ).to.equal(5000);
  });
  it("Should claim rewards", async function () {
    const depositWETHTx = await weth.deposit({
      value: ethers.utils.parseEther("1"),
    });
    await depositWETHTx.wait();

    // Approve the trading pool to spend the weth
    const approveTx = await weth.approve(
      tradingPool.address,
      ethers.utils.parseEther("1")
    );
    await approveTx.wait();
    // Mint a new NFT
    const mintTx = await testNFT.mint(owner.address);
    await mintTx.wait();
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
    const voteTx = await gaugeController.vote(0, tradingGauge.address, 10000);
    await voteTx.wait();

    // Get epoch time
    const epochPeriod = await votingEscrow.getEpochPeriod();
    // Let 2 epochs pass
    await time.increase(2 * epochPeriod.toNumber());

    // Save the balance before claiming
    const balanceBefore = await nativeToken.balanceOf(owner.address);

    // Call claim rewards statically
    const rewards = await tradingGauge.callStatic.claim();

    // Claim rewards
    const claimRewardsTx = await tradingGauge.claim();
    await claimRewardsTx.wait();

    // The user should have received the rewards
    expect(await nativeToken.balanceOf(owner.address)).to.equal(
      balanceBefore.add(rewards)
    );
  });
  it("Should use kick to update the boost for a user whose lock is over", async function () {
    //  Approve and lock some LE for the user
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
      Math.floor(Date.now() / 1000) + 3600 * 24 * 120 // 120 days
    );
    await lockTx2.wait();
    const depositWETHTx = await weth.deposit({
      value: ethers.utils.parseEther("1"),
    });
    await depositWETHTx.wait();

    // Approve the trading pool to spend the weth
    const approveTx = await weth.approve(
      tradingPool.address,
      ethers.utils.parseEther("1")
    );
    await approveTx.wait();
    // Mint a new NFT
    const mintTx = await testNFT.mint(owner.address);
    await mintTx.wait();
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

    // Let 30 days pass
    await time.increase(3600 * 24 * 30);

    expect(Number(await tradingGauge.getUserBoost(owner.address)))
      .to.be.greaterThan(10000)
      .and.lessThan(20000);

    // Kick the user's lock
    const kickTx = await tradingGauge.kick(0);
    await kickTx.wait();

    // The boost should be updated
    console.log("Get user boost");
    expect(await tradingGauge.getUserBoost(owner.address)).to.equal(10000);
  });
});
