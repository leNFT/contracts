const { expect, assert } = require("chai");
const load = require("../scripts/testDeploy/_loadTest.js");

describe("Voting Escrow", () => {
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

  it("Should get balance of user depositing", async function () {
    console.log("balanceOf(user)", await votingEscrow.balanceOf(owner.address));
    assert.isOk(await votingEscrow.balanceOf(owner.address));
  });
});
