const { expect } = require("chai");
const load = require("../helpers/_loadTest.js");
const { ethers } = require("hardhat");
const { time } = require("@nomicfoundation/hardhat-network-helpers");

describe("NativeTokenVesting", () => {
  load.loadTest(false);

  // Feed LE tokens to the vesting contract
  before(async () => {
    // Take a snapshot before the tests start
    snapshotId = await ethers.provider.send("evm_snapshot", []);
  });

  beforeEach(async function () {
    // Restore the blockchain state to the snapshot before each test
    await ethers.provider.send("evm_revert", [snapshotId]);

    // Take a snapshot before the tests start
    snapshotId = await ethers.provider.send("evm_snapshot", []);
  });
  it("Shoud get the vesting cap", async function () {
    const vestingCap = await nativeTokenVesting.getVestingCap();
    expect(vestingCap).to.equal(ethers.utils.parseEther("400000000"));
  });
  it("Set vesting for an account", async function () {
    const period = 60 * 60 * 24 * 30; // 30 days period
    const cliff = 60 * 60 * 24 * 30; // 30 days cliff
    const amount = 1000; // 1000 tokens

    // Should not be able to withdraw any tokens
    expect(
      await nativeTokenVesting.getAvailableToWithdraw(owner.address)
    ).to.equal(0);

    const setVestingTx = await nativeTokenVesting.setVesting(
      owner.address,
      period, // 30 days period
      cliff, // 30 days cliff
      amount // 1000 tokens
    );
    await setVestingTx.wait();

    // Get the time of the vesting
    const timeOfVesting = await time.latest();

    const vesting = await nativeTokenVesting.getVesting(owner.address);
    expect(vesting.period).to.equal(60 * 60 * 24 * 30);
    expect(vesting.cliff).to.equal(60 * 60 * 24 * 30);
    expect(vesting.amount).to.equal(1000);
    expect(vesting.timestamp).to.equal(timeOfVesting);
  });
  it("Should get the amount available to withdraw", async function () {
    const period = 60 * 60 * 24 * 30; // 30 days period
    const cliff = 60 * 60 * 24 * 30; // 30 days cliff
    const amount = 1000; // 1000 tokens
    const setVestingTx = await nativeTokenVesting.setVesting(
      owner.address,
      period, // 30 days period
      cliff, // 30 days cliff
      amount // 1000 tokens
    );
    await setVestingTx.wait();

    // Move 30 days forward
    await time.increase(period + 1);

    // Should be able to withdraw 500 tokens
    expect(
      await nativeTokenVesting.getAvailableToWithdraw(owner.address)
    ).to.equal(500);

    // Move 30 days forward
    await time.increase(period);

    // Should be able to withdraw 1000 tokens
    expect(
      await nativeTokenVesting.getAvailableToWithdraw(owner.address)
    ).to.equal(1000);
  });
  it("Should withdraw tokens", async function () {
    const period = 60 * 60 * 24 * 30; // 30 days period
    const cliff = 60 * 60 * 24 * 30; // 30 days cliff
    const amount = 1000; // 1000 tokens
    const setVestingTx = await nativeTokenVesting.setVesting(
      owner.address,
      period, // 30 days period
      cliff, // 30 days cliff
      amount // 1000 tokens
    );
    await setVestingTx.wait();

    // Move 30 days forward
    await time.increase(period + 1);

    // Get the balance before the withdraw
    const balanceBefore = await nativeToken.balanceOf(owner.address);

    // Withdraw 500 tokens
    const withdrawTx = await nativeTokenVesting.withdraw(500);
    await withdrawTx.wait();

    // Check the balance
    expect(await nativeToken.balanceOf(owner.address)).to.equal(
      balanceBefore.add(500)
    );

    // Should be able to withdraw 0 tokens
    expect(
      await nativeTokenVesting.getAvailableToWithdraw(owner.address)
    ).to.equal(0);

    // Move 30 days forward
    await time.increase(period);

    // Should be able to withdraw 500 tokens
    expect(
      await nativeTokenVesting.getAvailableToWithdraw(owner.address)
    ).to.equal(500);

    // Get the balance before the withdraw
    const balanceBefore2 = await nativeToken.balanceOf(owner.address);

    // Withdraw 500 tokens
    const withdrawTx2 = await nativeTokenVesting.withdraw(500);
    await withdrawTx2.wait();

    // Check the balance
    expect(await nativeToken.balanceOf(owner.address)).to.equal(
      balanceBefore2.add(500)
    );

    // Should be able to withdraw 0 tokens
    expect(
      await nativeTokenVesting.getAvailableToWithdraw(owner.address)
    ).to.equal(0);
  });
});
