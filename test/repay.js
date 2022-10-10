const { expect } = require("chai");
const load = require("../scripts/testDeploy/_loadTest.js");
const { getPriceSig } = require("./helpers/getPriceSig.js");

describe("Repay", function () {
  this.timeout(10000);
  load.loadTest();
  var tokenID;
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
    const mintTestTokenTx = await weth.mint(owner.address, 100);
    await mintTestTokenTx.wait();

    // Deposit the tokens into the market
    const approveTokenTx = await weth.approve(wethReserve.address, 100);
    await approveTokenTx.wait();
    const depositTx = await market.deposit(weth.address, 100);
    await depositTx.wait();

    // Find if the reserve tokens were sent accordingly
    expect(await wethReserve.balanceOf(owner.address)).to.equal(100);
  });
  it("Borrow using NFT asset as collateral", async function () {
    // Approve asset to be used by the market
    const approveNftTx = await testNFT.approve(market.address, tokenID);
    await approveNftTx.wait();

    const priceSig = getPriceSig(
      testNFT.address,
      0,
      "500000000000000000000", //Price is 500 Tokens
      "1694784579",
      nftOracle.address
    );

    // Ask the market to borrow underlying using the collateral
    const borrowTx = await market.borrow(
      weth.address,
      50,
      testNFT.address,
      tokenID,
      0,
      priceSig.request,
      priceSig
    );
    await borrowTx.wait();

    // Find if the borrower received the funds
    expect(await weth.balanceOf(owner.address)).to.equal(50);

    // Find if the protocol received the asset
    expect(await testNFT.ownerOf(tokenID)).to.equal(loanCenter.address);
  });
  it("Repay loan", async function () {
    const approveTokenTx = await weth.approve(wethReserve.address, 50);
    await approveTokenTx.wait();
    // Ask the market to repay underlying
    const repayTx = await market.repay(0, 50);
    await repayTx.wait();

    // Find if the protocol received the funds
    expect(await weth.balanceOf(wethReserve.address)).to.equal(100);

    // Find if the user received the asset
    expect(await testNFT.ownerOf(tokenID)).to.equal(owner.address);
  });
});
