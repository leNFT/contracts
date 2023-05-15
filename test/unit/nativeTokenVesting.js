const { expect } = require("chai");
const load = require("../helpers/_loadTest.js");
const { ethers } = require("hardhat");
const { time } = require("@nomicfoundation/hardhat-network-helpers");

describe("NativeTokenVesting", () => {
  load.loadTestAlways(false);

  // Feed LE tokens to the vesting contract
  beforeEach(async () => {
    const mintTokensTx = await nativeToken.mint(
      nativeTokenVesting.address,
      ethers.utils.parseEther("1000")
    );
    await mintTokensTx.wait();
  });

  it("Set vesting for an account", async function () {
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
    await time.increase(period);

    // Withdraw 500 tokens
    const withdrawTx = await nativeTokenVesting.withdraw(500);
    await withdrawTx.wait();

    // Check the balance
    expect(await nativeToken.balanceOf(owner.address)).to.equal(500);

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

    // Withdraw 500 tokens
    const withdrawTx2 = await nativeTokenVesting.withdraw(500);
    await withdrawTx2.wait();

    // Check the balance
    expect(await nativeToken.balanceOf(owner.address)).to.equal(1000);

    // Should be able to withdraw 0 tokens
    expect(
      await nativeTokenVesting.getAvailableToWithdraw(owner.address)
    ).to.equal(0);
  });
});
