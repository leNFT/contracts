const { expect } = require("chai");
const load = require("../helpers/_loadTest.js");
const { ethers } = require("hardhat");

describe("NativeToken", () => {
  load.loadTest(false);

  before(async function () {
    // Take a snapshot before the tests start
    snapshotId = await ethers.provider.send("evm_snapshot", []);
  });

  beforeEach(async function () {
    // Restore the blockchain state to the snapshot before each test
    await ethers.provider.send("evm_revert", [snapshotId]);

    // Take a snapshot before the tests start
    snapshotId = await ethers.provider.send("evm_snapshot", []);
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
