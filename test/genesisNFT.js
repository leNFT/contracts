const { expect } = require("chai");
const load = require("../scripts/testDeploy/_loadTest.js");

describe("GenesisNFT", function () {
  load.loadTest();
  it("Should mint a token", async function () {
    // Mint Genesis NFT
    const mintGenesisNFTTx = await genesisNFT.mint(2592000, {
      value: "300000000000000000",
    });
    await mintGenesisNFTTx.wait();

    // Find if the NFT was minted
    expect(await genesisNFT.ownerOf(genesisNFT.getMintCount())).to.equal(
      owner.address
    );
  });
  it("Should burn a token", async function () {
    // Increase time and Burn Genesis NFT
    await network.provider.send("evm_increaseTime", [2592000]);
    await network.provider.send("evm_mine");
    const balanceBefore = await owner.getBalance();
    const burnGenesisNFTTx = await genesisNFT.burn(
      await genesisNFT.getMintCount()
    );
    await burnGenesisNFTTx.wait();
    const balanceAfter = await owner.getBalance();

    // Find if the NFT was minted
    expect(balanceAfter.sub(balanceBefore).toString()).to.equal(
      "199780704229065376"
    );
  });
});
