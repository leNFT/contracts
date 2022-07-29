const { expect } = require("chai");
const { ethers } = require("hardhat");
const load = require("../scripts/testDeploy/_loadTest.js");

describe("Withdraw Native Token", function () {
  this.timeout(10000);
  load.loadTest();
  it("Should deposit native tokens into the vault", async function () {
    // Mint 10 native tokens to the callers address
    const mintNativeTokenTx = await nativeToken.mint(owner.address, 10);
    await mintNativeTokenTx.wait();

    // Deposit the tokens into the market
    const approveTokenTx = await nativeToken.approve(
      nativeTokenVault.address,
      10
    );
    await approveTokenTx.wait();
    const depositTx = await nativeTokenVault.deposit(10);
    await depositTx.wait();

    // Find if the reserve tokens were sent accordingly
    expect(await nativeTokenVault.getLockedBalance()).to.equal(10);
  });
  it("Should not be able to withdraw", async function () {
    await expect(nativeTokenVault.withdraw(10)).to.be.revertedWith(
      "Withdraw Request is not within valid timeframe"
    );
  });
  it("Should create an withdraw request", async function () {
    const createWithdrawRequestTx =
      await nativeTokenVault.createWithdrawRequest(10);
    await createWithdrawRequestTx.wait();

    const request = await nativeTokenVault.getWithdrawRequest(owner.address);
    expect(request.amount).to.equal(10);
  });
  it("Should be able to withdraw", async function () {
    //Simulate 8 days passing by
    await ethers.provider.send("evm_increaseTime", [86400 * 8]);
    await ethers.provider.send("evm_mine");

    const withdrawTx = await nativeTokenVault.withdraw(10);
    await withdrawTx.wait();

    // Find if the tokens were withdrawn
    expect(await nativeToken.balanceOf(owner.address)).to.equal(10);
  });
});
