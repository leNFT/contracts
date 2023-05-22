const { expect } = require("chai");
const { ethers } = require("hardhat");
const { BigNumber } = require("ethers");
const load = require("../helpers/_loadTest.js");
const { time } = require("@nomicfoundation/hardhat-network-helpers");

describe("Lending Pool & Gauge", function () {
  load.loadTest(false);

  before(async function () {
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
      addressesProvider.address,
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

  it("The lending gauge's lp token should be set to the lending pool", async function () {
    expect(await lendingGauge.lpToken()).to.equal(lendingPool.address);
  });
  it("The lending gauge's total supply should be its LP token balance", async function () {
    // Deposit into the lending pool
    const depositWETHTx = await weth.deposit({
      value: ethers.utils.parseEther("3"),
    });
    await depositWETHTx.wait();

    // Approve the lending pool to spend the weth
    const approveTx = await weth.approve(
      lendingPool.address,
      ethers.utils.parseEther("3")
    );
    await approveTx.wait();

    // Deposit into the pool
    const depositLendingPoolTx = await lendingPool.deposit(
      ethers.utils.parseEther("3"),
      owner.address
    );
    await depositLendingPoolTx.wait();

    // Approve the lending gauge to spend the lending pool tokens
    const approveLendingGaugeTx = await lendingPool.approve(
      lendingGauge.address,
      ethers.utils.parseEther("3")
    );
    await approveLendingGaugeTx.wait();

    // Deposit into the lending gauge
    const depositLendingGaugeTx = await lendingGauge.deposit(
      ethers.utils.parseEther("3")
    );
    await depositLendingGaugeTx.wait();

    // THe balance and token supply should be 3
    expect(await lendingPool.balanceOf(lendingGauge.address)).to.equal(
      await lendingGauge.totalSupply()
    );
    expect(await lendingGauge.totalSupply()).to.equal(
      ethers.utils.parseEther("3")
    );
  });

  it("Should be able to deposit and withdraw lending pool tokens in the corresponding gauge", async function () {
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
    expect(await lendingGauge.balanceOf(owner.address)).to.equal(
      ethers.utils.parseEther("1")
    );

    // Withdraw from the lending gauge
    const withdrawLendingGaugeTx = await lendingGauge.withdraw(
      ethers.utils.parseEther("1")
    );
    await withdrawLendingGaugeTx.wait();
  });
});
