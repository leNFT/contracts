const { expect } = require("chai");
const load = require("../scripts/testDeploy/_loadTest.js");

describe("Native Token Distribution", () => {
  load.loadTest();
  it("Should distribute rewards", async function () {
    // Distribute rewards in first epoch
    const distributeRewardsTx = await nativeToken.distributeRewards();
    await distributeRewardsTx.wait();

    //Find if first rewards were sent accordingly
    expect(await nativeToken.balanceOf(nativeTokenVault.address)).to.equal(
      "279999986772486772486772"
    );
  });

  it("Should vest developer rewards", async function () {
    // Distribute dev rewards
    await expect(
      nativeToken.mintDevRewards("1000000000000000000000")
    ).to.be.revertedWith("Amount bigger than allowed by vesting");

    //Change epoch and mint dev rewards
    await network.provider.send("evm_increaseTime", [30000000]);
    await network.provider.send("evm_mine");
    const mintDevRewards2Tx = await nativeToken.mintDevRewards(
      "6000000000000000000000000"
    );
    await mintDevRewards2Tx.wait();
    expect(await nativeToken.balanceOf(owner.address)).to.equal(
      "6000000000000000000000000"
    );
  });
});
