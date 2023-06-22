const { expect } = require("chai");
const { ethers } = require("hardhat");
const { BigNumber } = require("ethers");
const load = require("../helpers/_loadTest.js");
const { time } = require("@nomicfoundation/hardhat-network-helpers");

describe("Voting & Fees", function () {
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

  it("User should get all the fees if he's the only lock", async function () {
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

    const depositWETHTx = await weth.deposit({
      value: ethers.utils.parseEther("3"),
    });
    await depositWETHTx.wait();

    // Approve the trading pool to spend the weth
    const approveTx2 = await weth.approve(
      tradingPool.address,
      ethers.utils.parseEther("3")
    );
    await approveTx2.wait();
    // Mint two new NFTs
    const mintTx2 = await testNFT.mint(owner.address);
    await mintTx2.wait();
    const mintTx3 = await testNFT.mint(owner.address);
    await mintTx3.wait();
    // Approve the trading pool to spend the NFT
    const approveNFTTx = await testNFT.setApprovalForAll(
      tradingPool.address,
      true
    );
    await approveNFTTx.wait();
    // Add liquidity to the trading pool
    const depositTx = await tradingPool.addLiquidity(
      owner.address,
      0,
      [0, 1],
      ethers.utils.parseEther("1"),
      ethers.utils.parseEther("0.5"),
      exponentialCurve.address,
      "50",
      "500"
    );
    await depositTx.wait();

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

    // Advance 1 epochs
    const epochPeriod = await votingEscrow.getEpochPeriod();
    await time.increase(epochPeriod.toNumber());

    // Do a buy operation so we can gather some fees
    const buyTx = await tradingPool.buy(
      owner.address,
      [0],
      ethers.utils.parseEther("1")
    );
    await buyTx.wait();

    // Claim the rewards - should have nothing to claim since the lock can only claim fees after 1 epoch
    expect(await feeDistributor.callStatic.claim(weth.address, 0)).to.be.equal(
      0
    );

    // Do a buy operation so we can gather some fees
    const buyTx2 = await tradingPool.buy(
      owner.address,
      [1],
      ethers.utils.parseEther("1")
    );
    await buyTx2.wait();

    const epoch = (await votingEscrow.getEpoch(await time.latest())).toNumber();

    // Advange 1 epochs
    await time.increase(epochPeriod.toNumber());

    // The claimable should be the contract entire balance
    expect(await feeDistributor.callStatic.claim(weth.address, 0)).to.be.equal(
      await weth.balanceOf(feeDistributor.address)
    );

    // Should now be able to claim the fees gathered in the last epoch
    expect(await feeDistributor.callStatic.claim(weth.address, 0)).to.be.equal(
      await feeDistributor.getTotalFeesAt(weth.address, epoch)
    );

    // Claim the fees
    const claimTx = await feeDistributor.claim(weth.address, 0);
    await claimTx.wait();

    // Claimable amount and balance should be 0
    expect(await feeDistributor.callStatic.claim(weth.address, 0)).to.be.equal(
      0
    );
    expect(await weth.balanceOf(feeDistributor.address)).to.be.equal(0);
  });
  it("2 locks should share fees in a pro rata vote weight basis", async function () {
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

    const depositWETHTx = await weth.deposit({
      value: ethers.utils.parseEther("3"),
    });
    await depositWETHTx.wait();

    // Approve the trading pool to spend the weth
    const approveTx2 = await weth.approve(
      tradingPool.address,
      ethers.utils.parseEther("3")
    );
    await approveTx2.wait();
    // Mint two new NFTs
    const mintTx2 = await testNFT.mint(owner.address);
    await mintTx2.wait();
    const mintTx3 = await testNFT.mint(owner.address);
    await mintTx3.wait();
    // Approve the trading pool to spend the NFT
    const approveNFTTx = await testNFT.setApprovalForAll(
      tradingPool.address,
      true
    );
    await approveNFTTx.wait();
    // Add liquidity to the trading pool
    const depositTx = await tradingPool.addLiquidity(
      owner.address,
      0,
      [0, 1],
      ethers.utils.parseEther("1"),
      ethers.utils.parseEther("0.5"),
      exponentialCurve.address,
      "50",
      "500"
    );
    await depositTx.wait();

    // Create a two locks with the LE
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

    // Do a buy operation so we can gather some fees
    const buyTx = await tradingPool.buy(
      owner.address,
      [0],
      ethers.utils.parseEther("1")
    );
    await buyTx.wait();

    // Advange 1 epochs
    const epochPeriod = await votingEscrow.getEpochPeriod();
    await time.increase(epochPeriod.toNumber());

    // Claim the rewards, should have nothing to claim since the locks can only claim fees after 1 epoch
    expect(await feeDistributor.callStatic.claim(weth.address, 0)).to.be.equal(
      0
    );
    expect(await feeDistributor.callStatic.claim(weth.address, 1)).to.be.equal(
      0
    );

    // Do a buy operation so we can gather some fees
    const buyTx2 = await tradingPool.buy(
      owner.address,
      [1],
      ethers.utils.parseEther("1")
    );
    await buyTx2.wait();

    const epoch = (await votingEscrow.getEpoch(await time.latest())).toNumber();

    // Advange 1 epochs
    await time.increase(epochPeriod.toNumber());

    // Should now be able to claim the fees gathered in the last epoch
    expect(await feeDistributor.callStatic.claim(weth.address, 0)).to.be.equal(
      BigNumber.from(
        await feeDistributor.getTotalFeesAt(weth.address, epoch)
      ).div(2)
    );
    expect(await feeDistributor.callStatic.claim(weth.address, 1)).to.be.equal(
      BigNumber.from(
        await feeDistributor.getTotalFeesAt(weth.address, epoch)
      ).div(2)
    );
  });
});
