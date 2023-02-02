const { expect } = require("chai");
const { getPriceSig } = require("./helpers/getPriceSig.js");
const load = require("../scripts/testDeploy/_loadTest.js");

describe("Borrow", function () {
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
  it("Deposit underlying to the lending pool", async function () {
    const createLendingPoolTx = await lendingMarket.createLendingPool(
      testNFT.address,
      weth.address
    );
    await createLendingPoolTx.wait();
    const depositETHTx = await wethGateway.depositETH(
      await lendingMarket.getLendingPool(testNFT.address, weth.address),
      { value: "1000000000000000000" }
    );
    await depositETHTx.wait();
  });
  it("Borrow using NFT asset as collateral", async function () {
    // Approve asset to be used by the lending market
    const approveNftTx = await testNFT.approve(wethGateway.address, tokenID);
    await approveNftTx.wait();

    const priceSig = getPriceSig(
      testNFT.address,
      0,
      "8000000000000000", //Price of 0.008 ETH
      "1694784579",
      nftOracle.address
    );

    // Ask the market to borrow underlying using the collateral
    const borrowTx = await wethGateway.borrowETH(
      "100000000000000",
      testNFT.address,
      tokenID,
      0,
      priceSig.request,
      priceSig
    );
    await borrowTx.wait();

    // Find if the protocol received the asset
    expect(await testNFT.ownerOf(tokenID)).to.equal(loanCenter.address);
  });
});
