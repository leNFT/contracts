const { expect } = require("chai");
const { ethers } = require("hardhat");
const { BigNumber } = require("ethers");
const load = require("../helpers/_loadTest.js");
const { getPriceSig } = require("../helpers/getPriceSig.js");
const { time } = require("@nomicfoundation/hardhat-network-helpers");

describe("FeeDistributor", function () {
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

  it("Should checkpoint the fees", async function () {
    const epoch = await votingEscrow.getEpoch(await time.latest());
    expect(await feeDistributor.getTotalFeesAt(weth.address, epoch)).to.equal(
      0
    );
    // Mint some weth to the fee Distributor
    const depositTx = await weth.deposit({
      value: ethers.utils.parseEther("1"),
    });
    await depositTx.wait();
    const transferTx = await weth.transfer(
      feeDistributor.address,
      ethers.utils.parseEther("1")
    );
    await transferTx.wait();

    // Checkpoint the fees
    const checkpointTx = await feeDistributor.checkpoint(weth.address);
    await checkpointTx.wait();

    // Check the fees
    expect(await feeDistributor.getTotalFeesAt(weth.address, epoch)).to.equal(
      ethers.utils.parseEther("1")
    );
  });

  it("Should salvage fees", async function () {
    const depositTx = await weth.deposit({
      value: ethers.utils.parseEther("1"),
    });
    await depositTx.wait();
    // Send some weth to the fee Distributor
    const transferTx = await weth.transfer(
      feeDistributor.address,
      ethers.utils.parseEther("1")
    );
    await transferTx.wait();

    // Checkpoint the fees
    const checkpointTx = await feeDistributor.checkpoint(weth.address);
    await checkpointTx.wait();

    // Go to 1 epoch in the future
    await time.increase(await votingEscrow.getEpochPeriod());

    const epoch = await votingEscrow.getEpoch(await time.latest());

    // Salvage the fees from epoch
    const salvageTx = await feeDistributor.salvageFees(weth.address, epoch - 1);
    await salvageTx.wait();

    // Check the fees
    expect(
      await feeDistributor.getTotalFeesAt(weth.address, epoch - 1)
    ).to.equal(0);
    expect(await feeDistributor.getTotalFeesAt(weth.address, epoch)).to.equal(
      ethers.utils.parseEther("1")
    );
  });
  it("Should claim fees", async function () {
    const depositTx = await weth.deposit({
      value: ethers.utils.parseEther("1"),
    });
    await depositTx.wait();
    // Send some weth to the fee Distributor
    const transferTx = await weth.transfer(
      feeDistributor.address,
      ethers.utils.parseEther("1")
    );
    await transferTx.wait();

    // Create a lock with the LE
    const approveTx = await nativeToken.approve(
      votingEscrow.address,
      ethers.utils.parseEther("1")
    );
    await approveTx.wait();
    const lockTx = await votingEscrow.createLock(
      owner.address,
      ethers.utils.parseEther("1"),
      Math.floor(Date.now() / 1000) + 3600 * 24 * 30 // 30 days
    );
    await lockTx.wait();

    // Go to 1 epoch in the future because users can't claim fees from epoch 0
    await time.increase(await votingEscrow.getEpochPeriod());

    // Checkpoint the fees
    const checkpointTx = await feeDistributor.checkpoint(weth.address);
    await checkpointTx.wait();

    // Go to 1 epoch in the future so the epoch ends and the user can claim the fees
    await time.increase(await votingEscrow.getEpochPeriod());

    // Claim the fees from epoch 1
    const claimTx = await feeDistributor.claim(weth.address, 0);
    await claimTx.wait();

    // Check if the user received the fees
    expect(await weth.balanceOf(owner.address)).to.equal(
      ethers.utils.parseEther("1")
    );
  });
  it("Should claim fees for multiple vote tokens", async function () {
    const depositTx = await weth.deposit({
      value: ethers.utils.parseEther("1"),
    });
    await depositTx.wait();
    // Send some weth to the fee Distributor
    const transferTx = await weth.transfer(
      feeDistributor.address,
      ethers.utils.parseEther("1")
    );
    await transferTx.wait();

    // Create a lock with the LE
    const approveTx = await nativeToken.approve(
      votingEscrow.address,
      ethers.utils.parseEther("2")
    );
    await approveTx.wait();
    const lockTx = await votingEscrow.createLock(
      owner.address,
      ethers.utils.parseEther("1"),
      Math.floor(Date.now() / 1000) + 3600 * 24 * 30 // 30 days
    );
    await lockTx.wait();
    const lockTx2 = await votingEscrow.createLock(
      owner.address,
      ethers.utils.parseEther("1"),
      Math.floor(Date.now() / 1000) + 3600 * 24 * 30 // 30 days
    );
    await lockTx2.wait();

    // Go to 1 epoch in the future because users can't claim fees from epoch 0
    await time.increase(await votingEscrow.getEpochPeriod());

    // Checkpoint the fees
    const checkpointTx = await feeDistributor.checkpoint(weth.address);
    await checkpointTx.wait();

    // Go to 1 epoch in the future so the epoch ends and the user can claim the fees
    await time.increase(await votingEscrow.getEpochPeriod());

    // Claim the fees from epoch 1
    const claimBatchTx = await feeDistributor.claimBatch(weth.address, [0, 1]);
    await claimBatchTx.wait();

    // Check if the user received the fees
    expect(await weth.balanceOf(owner.address)).to.equal(
      ethers.utils.parseEther("1")
    );
  });
});
