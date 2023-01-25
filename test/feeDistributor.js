const { expect, assert } = require("chai");
const load = require("../scripts/testDeploy/_loadTest.js");

describe("Fee Distributor ", () => {
  load.loadTest();
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
      "10000000000000000000",
      Math.floor(Date.now() / 1000) + 86400 * 100
    );
    console.log(Math.floor(Date.now() / 1000) + 86400 * 100);
  });

  it("Should deposit into the fee distributor contract", async function () {
    // Add 1 weeks to the time
    await ethers.provider.send("evm_increaseTime", [86400 * 7]);

    // Mint weth tokens to the fee distributor contract
    const mintTestTokenTx = await weth.mint(
      feeDistributor.address,
      "100000000000000"
    );
    await mintTestTokenTx.wait();

    // Call for a fee checkpoint on the fee distributor contract
    const checkpointTx = await feeDistributor.checkpoint(weth.address);
    await checkpointTx.wait();
  });
  it("Should be able to claim the tokens after the epoch is over", async function () {
    // Add 2 weeks to the time
    await ethers.provider.send("evm_increaseTime", [86400 * 7]);

    // Claim fees
    const claimFeesTx = await feeDistributor.claim(weth.address);
    await claimFeesTx.wait();

    expect(await weth.balanceOf(owner.address)).to.equal("100000000000000");
  });
});