const { expect, assert } = require("chai");
const load = require("../helpers/_loadTest.js");
const { time } = require("@nomicfoundation/hardhat-network-helpers");

describe("Fee Distributor ", () => {
  load.loadTest(false);
  it("Should lock tokens", async function () {
    // Approve tokens for use by the voting escrow contract
    const approveTokenTx = await nativeToken.approve(
      votingEscrow.address,
      "10000000000000000000"
    );
    await approveTokenTx.wait();

    console.log("Approved tokens");

    //Lock 10 tokens for 100 days
    await votingEscrow.createLock(
      owner.address,
      "10000000000000000000",
      Math.floor(Date.now() / 1000) + 86400 * 100
    );
    console.log(Math.floor(Date.now() / 1000) + 86400 * 100);
  });

  it("Should deposit into the fee distributor contract", async function () {
    const epochPeriod = await votingEscrow.getEpochPeriod();
    await time.increase(epochPeriod.toNumber());

    // Mint weth tokens to the fee distributor contract
    const mintNativeTokenTx = await nativeToken.transfer(
      feeDistributor.address,
      "10000000000000000000"
    );
    await mintNativeTokenTx.wait();

    console.log("TRansfered tokens");

    // Call for a fee checkpoint on the fee distributor contract
    const checkpointTx = await feeDistributor.checkpoint(nativeToken.address);
    await checkpointTx.wait();
  });
  it("Should be able to add to the unlock time", async function () {
    //Lock 10 tokens for 100 days
    await votingEscrow.increaseUnlockTime(
      0,
      Math.floor(Date.now() / 1000) + 86400 * 200
    );
  });
  it("Should be able to claim the tokens after the epoch is over", async function () {
    const epochPeriod = await votingEscrow.getEpochPeriod();
    await time.increase(epochPeriod.toNumber());

    // SAve the balance before claiming
    const balanceBefore = await nativeToken.balanceOf(owner.address);

    // Claim fees
    const claimFeesTx = await feeDistributor.claim(nativeToken.address, 0);
    await claimFeesTx.wait();

    console.log("Claimed fees");

    // Check if the balance has increased
    expect(await nativeToken.balanceOf(owner.address)).to.equal(
      balanceBefore.add("10000000000000000000")
    );
  });
});
