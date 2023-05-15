const { expect, assert } = require("chai");
const load = require("../helpers/_loadTest.js");

describe("Fee Distributor ", () => {
  load.loadTest(false);
  it("Should lock tokens", async function () {
    // Mint 10 native tokens to the callers address
    const mintNativeTokenTx = await nativeToken.mint(
      owner.address,
      "10000000000000000000"
    );
    await mintNativeTokenTx.wait();

    console.log("Minted tokens");

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
    await ethers.provider.send("evm_increaseTime", [6 * 3600]);
    // Mine a new block
    await ethers.provider.send("evm_mine", []);

    // Mint weth tokens to the fee distributor contract
    const mintNativeTokenTx = await nativeToken.mint(
      feeDistributor.address,
      "10000000000000000000"
    );
    await mintNativeTokenTx.wait();

    console.log("Minted tokens");

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
    await ethers.provider.send("evm_increaseTime", [24 * 3600]);
    // Mine a new block
    await ethers.provider.send("evm_mine", []);

    // Claim fees
    const claimFeesTx = await feeDistributor.claim(nativeToken.address, 0);
    await claimFeesTx.wait();

    console.log("Claimed fees");

    expect(await nativeToken.balanceOf(owner.address)).to.equal(
      "10000000000000000000"
    );
  });
});
