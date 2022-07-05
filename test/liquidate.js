const { expect } = require("chai");
const load = require("../scripts/_load");

describe("Liquidate", function () {
  load.loadTest();
  var tokenId;
  it("Create NFT asset", async function () {
    // Mint NFT collateral
    const mintTestNftTx = await testNFT.mint(owner.address);
    tokenIDReceipt = await mintTestNftTx.wait();
    const event = tokenIDReceipt.events.find((event) => event.event === "Mint");
    tokenID = event.args.tokenId.toNumber();

    // Find if the NFT was minted accordingly
    expect(await testNFT.ownerOf(tokenID)).to.equal(owner.address);
  });
  it("Deposit underlying to the reserve", async function () {
    // Mint 100 test tokens to the callers address
    const mintTestTokenTx = await testToken.mint(owner.address, 100);
    await mintTestTokenTx.wait();

    // Deposit the tokens into the market
    const approveTokenTx = await testToken.approve(testReserve.address, 100);
    await approveTokenTx.wait();
    const depositTx = await market.deposit(testToken.address, 100);
    await depositTx.wait();

    // Find if the reserve tokens were sent accordingly
    expect(await testReserve.balanceOf(owner.address)).to.equal(100);
  });
  it("Borrow using NFT asset as collateral", async function () {
    // Approve asset to be used by the market
    const approveNftTx = await testNFT.approve(market.address, tokenID);
    await approveNftTx.wait();

    // Ask the market to borrow underlying using the collateral
    const borrowTx = await market.borrow(
      testToken.address,
      50,
      testNFT.address,
      tokenID
    );
    await borrowTx.wait();

    // Find if the borrower received the funds
    expect(await testToken.balanceOf(owner.address)).to.equal(50);

    // Find if the protocol received the asset
    expect(await testNFT.ownerOf(tokenID)).to.equal(loanCenter.address);
  });
  it("Liquidate loan", async function () {
    // Change nft collection price
    const changeNftFloorPriceTx = await nftOracle.addFloorPriceData(
      testNFT.address,
      100
    );
    await changeNftFloorPriceTx.wait();

    //Liquidate the loan
    const liquidateTx = await market.liquidate(0);
    await liquidateTx.wait();

    // Find if the liquidater received the asset
    expect(await testNFT.ownerOf(tokenID)).to.equal(owner.address);
  });
});
