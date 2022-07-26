const { expect } = require("chai");
const load = require("../scripts/testDeploy/_loadTest.js");

describe("Liquidate", function () {
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

    // Ask the market to borrow 100 tokens underlying using the collateral (worth 500 tokens with mex collateral 20%)
    const borrowTx = await market.borrow(
      testToken.address,
      "100000000000000000000",
      testNFT.address,
      tokenId
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
    const changeNftFloorPriceTx = await nftOracle.addFloorPriceData(
      testNFT.address,
      "400000000000000000000"
    );
    await changeNftFloorPriceTx.wait();

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
    const liquidateTx = await market.connect(addr1).liquidate(0);
    await liquidateTx.wait();

    // Find if the liquidator received the asset
    expect(await testNFT.ownerOf(tokenId)).to.equal(addr1.address);

    // Find if the liquidator sent the token
    expect(await testToken.balanceOf(addr1.address)).to.equal(0);

    //Find if the reserve debt was paid
    expect(await testToken.balanceOf(testReserve.address)).to.equal(
      "1000000001000000000000"
    );

    // Find if the borrower received the funds left from the liquidations
    expect(await testToken.balanceOf(owner.address)).to.equal(
      "319999999000000000000"
    );

    //Find if the liquidation fee was paid
    expect(await testToken.balanceOf(feeTreasuryAddress)).to.equal(
      "8000000000000000000"
    );
  });
});
