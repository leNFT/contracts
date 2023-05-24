const { expect, assert } = require("chai");
const load = require("../helpers/_loadTest.js");

describe("Voting Escrow", () => {
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

  it("Should get balance of user depositing", async function () {
    console.log("balanceOf(user)", await votingEscrow.balanceOf(owner.address));
    assert.isOk(await votingEscrow.balanceOf(owner.address));
  });
  it("Should claim rebates", async function () {
    // Let 6 hours pass
    await network.provider.send("evm_increaseTime", [21600]);
    await network.provider.send("evm_mine");
    await votingEscrow.claimRebates(0);
    console.log("Claimed rebates");

    // Check balance of user
    console.log("balanceOf(user)", await nativeToken.balanceOf(owner.address));
  });
});
