const { expect } = require("chai");
const load = require("../scripts/testDeploy/_loadTest.js");

describe("Liquidate", function () {
  this.timeout(10000);
  load.loadTest();
  var tokenId;
  it("Create NFT asset", async function () {
    // Mint NFT collateral
    const mintTestNftTx = await testNFT.mint(owner.address);
    tokenIDReceipt = await mintTestNftTx.wait();
    const event = tokenIDReceipt.events.find((event) => event.event === "Mint");
    tokenId = event.args.tokenId.toNumber();

    // Find if the NFT was minted accordingly
    expect(await testNFT.ownerOf(tokenId)).to.equal(owner.address);
  });
  it("Deposit underlying to the reserve", async function () {
    // Mint 1000 test tokens to the callers address
    const mintTestTokenTx = await testToken.mint(
      owner.address,
      "1000000000000000000000"
    );
    await mintTestTokenTx.wait();

    // Deposit the 1000 tokens into the market
    const approveTokenTx = await testToken.approve(
      testReserve.address,
      "1000000000000000000000"
    );
    await approveTokenTx.wait();
    const depositTx = await market.deposit(
      testToken.address,
      "1000000000000000000000"
    );
    await depositTx.wait();

    // Find if the reserve tokens were sent accordingly
    expect(await testReserve.balanceOf(owner.address)).to.equal(
      "1000000000000000000000"
    );
  });
  it("Borrow using NFT asset as collateral", async function () {
    // Approve asset to be used by the market
    const approveNftTx = await testNFT.approve(market.address, tokenId);
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

    // Ask the market to borrow 100 tokens underlying using the collateral (worth 500 tokens with mex collateral 20%)
    const borrowTx = await market.borrow(
      testToken.address,
      "100000000000000000000",
      testNFT.address,
      tokenId,
      request,
      serverPacket
    );
    await borrowTx.wait();

    // Find if the borrower received the funds
    expect(await testToken.balanceOf(owner.address)).to.equal(
      "100000000000000000000"
    );

    // Find if the protocol received the asset
    expect(await testNFT.ownerOf(tokenId)).to.equal(loanCenter.address);
  });
  it("Liquidate loan", async function () {
    // Change nft collection price to 400 ETH
    const newRequest =
      "0x0000000000000000000000000000000000000000000000000000000000000000";
    const newServerPacket = {
      v: 28,
      r: "0x36c8613b4c609103c67dccd29e6d187b448fefa678830ab3abb84ce652617132",
      s: "0x2d7026dd58a80963ebd2132bda3e9781693724d75b6d183c022640d156cdc3ef",
      request:
        "0x0000000000000000000000000000000000000000000000000000000000000000",
      deadline: "1659961474",
      payload:
        "0x0000000000000000000000000165878a594ca255338adfa4d48449f69242eb8f0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000015af1d78b58c400000",
    };

    //Mint 328 tokens to liquidator se he can pay the liquidation
    const mintTestTokenTx = await testToken.mint(
      addr1.address,
      "328000000000000000000"
    );
    await mintTestTokenTx.wait();
    // Approve the tokens to the market
    const approveTokenTx = await testToken
      .connect(addr1)
      .approve(market.address, "328000000000000000000");
    await approveTokenTx.wait();

    //Liquidate the loan
    console.log("Liquidating...");
    const liquidateTx = await market
      .connect(addr1)
      .liquidate(0, newRequest, newServerPacket);
    await liquidateTx.wait();

    // Find if the liquidator received the asset
    expect(await testNFT.ownerOf(tokenId)).to.equal(addr1.address);

    // Find if the liquidator sent the token
    expect(await testToken.balanceOf(addr1.address)).to.equal(0);

    //Find if the reserve debt was paid
    expect(await testToken.balanceOf(testReserve.address)).to.equal(
      "1000000000000000000000"
    );

    // Find if the borrower received the funds left from the liquidations
    expect(await testToken.balanceOf(owner.address)).to.equal(
      "320000000000000000000"
    );

    //Find if the liquidation fee was paid
    expect(await testToken.balanceOf(feeTreasuryAddress)).to.equal(
      "8000000000000000000"
    );
  });
});
