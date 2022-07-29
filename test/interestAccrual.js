const { expect } = require("chai");
const { ethers } = require("hardhat");
const load = require("../scripts/testDeploy/_loadTest.js");

describe("InterestAccrual", function () {
  this.timeout(10000);
  load.loadTest();
  var tokenID;
  it("Create NFT asset", async function () {
    // Mint NFT collateral
    const mintTestNftTx = await testNFT.mint(owner.address);
    const tokenIDReceipt = await mintTestNftTx.wait();
    const event = tokenIDReceipt.events.find((event) => event.event === "Mint");
    tokenID = event.args.tokenId.toNumber();

    // Find if the NFT was minted accordingly
    expect(await testNFT.ownerOf(tokenID)).to.equal(owner.address);
  });
  it("Deposit underlying to the reserve", async function () {
    // Mint  test tokens to the callers address
    const mintTestTokenTx = await testToken.mint(
      owner.address,
      "1000000000000000000"
    );
    await mintTestTokenTx.wait();

    // Deposit the tokens into the market
    const approveTokenTx = await testToken.approve(
      testReserve.address,
      "1000000000000000000"
    );
    await approveTokenTx.wait();
    const depositTx = await market.deposit(
      testToken.address,
      "1000000000000000000"
    );
    await depositTx.wait();

    // Find if the reserve tokens were sent accordingly
    expect(await testReserve.balanceOf(owner.address)).to.equal(
      "1000000000000000000"
    );
  });
  it("Borrow using NFT asset as collateral", async function () {
    // Approve asset to be used by the market
    const approveNftTx = await testNFT.approve(market.address, tokenID);
    await approveNftTx.wait();

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

    // Ask the market to borrow underlying using the collateral (0.1 tokens)
    const borrowTx = await market.borrow(
      testToken.address,
      "100000000000000000",
      testNFT.address,
      tokenID,
      request,
      serverPacket
    );
    await borrowTx.wait();

    // Find if the borrower received the funds (0.1 tokens)
    expect(await testToken.balanceOf(owner.address)).to.equal(
      "100000000000000000"
    );

    // Find if the protocol received the asset
    expect(await testNFT.ownerOf(tokenID)).to.equal(loanCenter.address);
  });
  it("Accrue the right amount of interest", async function () {
    //Simulate 24 hours of interest
    await ethers.provider.send("evm_increaseTime", [86400]);
    await ethers.provider.send("evm_mine");
    console.log(await loanCenter.getLoanDebt(tokenID));
    expect(await loanCenter.getLoanDebt(tokenID)).to.equal(
      "100027397000000000"
    );
  });
});
