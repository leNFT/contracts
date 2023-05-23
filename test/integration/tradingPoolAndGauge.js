const { expect } = require("chai");
const { ethers } = require("hardhat");
const { BigNumber } = require("ethers");
const load = require("../helpers/_loadTest.js");
const { time } = require("@nomicfoundation/hardhat-network-helpers");

describe("Trading Pool & Gauge", function () {
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

  it("The trading gauge's lp token should be set to the trading pool", async function () {
    expect(await tradingGauge.getLPToken()).to.equal(tradingPool.address);
  });
  it("The trading gauge's total supply should be its LP token balance", async function () {
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

    // The total supply should be the trading gauge's balance
    expect(await tradingGauge.getTotalSupply()).to.equal(
      await tradingPool.balanceOf(tradingGauge.address)
    );
  });
  it("Should be able to deposit and withdraw trading pool tokens in the corresponding gauge", async function () {
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
    await expect(tradingGauge.deposit(0)).to.not.be.reverted;

    // Withdraw from the trading gauge
    await expect(tradingGauge.withdraw(0)).to.not.be.reverted;
  });
});
