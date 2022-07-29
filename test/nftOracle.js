const { expect } = require("chai");
const load = require("../scripts/testDeploy/_loadTest.js");

describe("NFT Oracle", function () {
  this.timeout(10000);
  load.loadTest();
  it("Get Max ETH collateral for token", async function () {
    const request =
      "0x0000000000000000000000000000000000000000000000000000000000000000";
    const serverPacket = {
      v: 28,
      r: "0x063dbd7938134346a003f46dd4ff246d323c663e42f8653bea0bb197fdee80da",
      s: "0x5d4aeae17041daee885ac0d9ab53196cffc31f8a4b436ff6cc4e4777928a5cb9",
      request:
        "0x0000000000000000000000000000000000000000000000000000000000000000",
      deadline: "1659961474",
      payload:
        "0x0000000000000000000000000165878a594ca255338adfa4d48449f69242eb8f000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000001b1ae4d6e2ef500000",
    };
    const maxCollateral = await nftOracle.getTokenMaxETHCollateral(
      owner.address,
      testNFT.address,
      0,
      request,
      serverPacket
    );

    // Find if the NFT was minted accordingly
    expect(maxCollateral).to.equal("100000000000000000000");
  });
});
