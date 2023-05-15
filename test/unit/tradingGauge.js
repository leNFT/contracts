const { expect } = require("chai");
const load = require("../helpers/_loadTest.js");
const { ethers } = require("hardhat");
const { time } = require("@nomicfoundation/hardhat-network-helpers");

describe("TradingGauge", () => {
  load.loadTestAlways(false);

  // Create a new trading pool and its associated trading gauge
  beforeEach(async () => {
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
      addressesProvider.address,
      tradingPool.address
    );
    await tradingGauge.deployed();

    // Add both the trading gauge to the gauge controller
    const addGaugeTx = await gaugeController.addGauge(tradingGauge.address);
    await addGaugeTx.wait();
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
    expect(await tradingGauge.userLPValue(owner.address)).to.equal(lpValue);

    // The total value should be the same a the lp he deposited
    expect(await tradingGauge.totalLPValue()).to.equal(lpValue);

    // The trading gauge should own the liquidity pair NFT
    expect(await tradingPool.ownerOf(0)).to.equal(tradingGauge.address);

    // THe balance for the user should be 1
    expect(await tradingGauge.balanceOf(owner.address)).to.equal(1);
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
    expect(await tradingGauge.userLPValue(owner.address)).to.equal(0);
    expect(await tradingGauge.totalSupply()).to.equal(
      ethers.utils.parseEther("0")
    );

    // The user should own the liquidity pair NFT
    expect(await tradingPool.ownerOf(0)).to.equal(owner.address);

    // THe balance for the user should be 0
    expect(await tradingGauge.balanceOf(owner.address)).to.equal(0);
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

    expect(await tradingGauge.userBoost(owner.address)).to.equal(20000);
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

    expect(await tradingGauge.userMaturityMultiplier(owner.address)).to.equal(
      5000
    );
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

    // Mint some LE tokens so we can vote
    const mintLETx = await nativeToken.mint(
      owner.address,
      ethers.utils.parseEther("1")
    );
    await mintLETx.wait();

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

    // Claim rewards
    const claimRewardsTx = await tradingGauge.claim();
    await claimRewardsTx.wait();

    // The user should have all the rewards for the epoch
    expect(await nativeToken.balanceOf(owner.address)).to.equal(
      "1990911999999999999"
    );
  });
});
