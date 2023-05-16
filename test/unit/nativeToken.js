const { expect } = require("chai");
const load = require("../helpers/_loadTest.js");
const { ethers } = require("hardhat");

describe("NativeToken", () => {
  load.loadTestAlways(false);

  it("Should mint tokens", async function () {
    const mintTokensTx = await nativeToken.mint(owner.address, 100);
    await mintTokensTx.wait();

    expect(await nativeToken.balanceOf(owner.address)).to.equal(100);
  });
  it("Should throw an error when using mintGaugeRewards", async function () {
    // Should throw an errir when trying to mint tokens via any other function
    await expect(
      nativeToken.mintGaugeRewards(owner.address, 100)
    ).to.be.revertedWith("NT:MGR:NOT_GAUGE");
  });
  it("Should throw an error when using mintGenesisTokens", async function () {
    // Should throw an errir when trying to mint tokens via any other function
    await expect(nativeToken.mintGenesisTokens(100)).to.be.revertedWith(
      "NT:MGT:NOT_GENESIS"
    );
  });
  it("Should throw an error when using mintRebates", async function () {
    // Should throw an errir when trying to mint tokens via any other function
    await expect(
      nativeToken.mintRebates(owner.address, 100)
    ).to.be.revertedWith("NT:MR:NOT_VOTING_ESCROW");
  });
  it("Should throw an error when using burnGenesisTokens", async function () {
    // Should throw an errir when trying to mint tokens via any other function
    await expect(nativeToken.burnGenesisTokens(100)).to.be.revertedWith(
      "NT:BGT:NOT_GENESIS"
    );
  });
});