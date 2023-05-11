const { expect } = require("chai");
const { getPriceSig } = require("./helpers/getPriceSig.js");
const load = require("./helpers/_loadTest.js");

describe("Liquidate", function () {
  load.loadTest();
  var tokenID;
  it("Create NFT asset 1", async function () {
    // Mint 2 NFT collaterals
    const mintTestNftTx = await testNFT.mint(owner.address);
    const tokenIDReceipt = await mintTestNftTx.wait();
    const event = tokenIDReceipt.events.find((event) => event.event === "Mint");
    tokenID1 = event.args.tokenId.toNumber();

    // Find if the NFT was minted accordingly
    expect(await testNFT.ownerOf(tokenID1)).to.equal(owner.address);
  });
  it("Create NFT asset 2", async function () {
    // Mint 2 NFT collaterals
    const mintTestNftTx = await testNFT.mint(owner.address);
    const tokenIDReceipt = await mintTestNftTx.wait();
    const event = tokenIDReceipt.events.find((event) => event.event === "Mint");
    tokenID2 = event.args.tokenId.toNumber();

    // Find if the NFT was minted accordingly
    expect(await testNFT.ownerOf(tokenID2)).to.equal(owner.address);
  });
  it("Deposit underlying to the lending pool", async function () {
    const createLendingPoolTx = await lendingMarket.createLendingPool(
      testNFT.address,
      weth.address
    );
    await createLendingPoolTx.wait();
    const depositTx = await wethGateway.depositLendingPool(
      await lendingMarket.getLendingPool(testNFT.address, weth.address),
      { value: "1000000000000000000" }
    );
    await depositTx.wait();
  });
  it("Borrow using NFT asset as collateral", async function () {
    // Approve assets to be used by the lending market
    const approveNftTx1 = await testNFT.approve(wethGateway.address, tokenID1);
    await approveNftTx1.wait();
    const approveNftTx2 = await testNFT.approve(wethGateway.address, tokenID2);
    await approveNftTx2.wait();

    const priceSig = getPriceSig(
      testNFT.address,
      [tokenID1, tokenID2],
      "8000000000000000000", //Price of 800 ETH
      "1694784579",
      nftOracle.address
    );
    console.log("Got price sig for: ", [tokenID1, tokenID2]);
    // Ask the market to borrow underlying using the collateral
    const balanceBeforeBorrow = await owner.getBalance();
    console.log("Balance before borrow: ", balanceBeforeBorrow.toString());
    const borrowTx = await wethGateway.borrow(
      //"1000000000000000",
      "100000000000000000", // - audit - borrow 100x the amount (same value in ether)
      testNFT.address,
      [tokenID1, tokenID2],
      0,
      priceSig.request,
      priceSig
    );
    const receipt = await borrowTx.wait();
    console.log("Gas used: ", receipt.gasUsed.toString());
    const balanceAfterBorrow = await owner.getBalance();
    console.log("Balance after borrow: ", balanceAfterBorrow.toString());
    const gasUsedETH = receipt.effectiveGasPrice * receipt.gasUsed;

    // Find if the user received the borrowed amountS
    expect(
      balanceAfterBorrow.sub(balanceBeforeBorrow).add(gasUsedETH)
    ).to.be.eq("100000000000000000"); // - audit

    // Find if the protocol received the asset
    expect(await testNFT.ownerOf(tokenID1)).to.equal(loanCenter.address);
    expect(await testNFT.ownerOf(tokenID2)).to.equal(loanCenter.address);
  });
  it("Start the liquidation auction", async function () {
    const priceSig = getPriceSig(
      testNFT.address,
      [tokenID1, tokenID2],
      "800000000000000", //Price of 0.08 ETH (1000x lower than the borrow)
      "1694784579",
      nftOracle.address
    );
    console.log("Got price sig for: ", [tokenID1, tokenID2]);
    // Get WETH from the weth contract
    const getWETHTx = await weth.deposit({ value: "100000000000000000" });
    await getWETHTx.wait();
    console.log("owner.address", owner.address);
    console.log("weth.address", weth.address);
    // Approve the WETH to be used by the lending market
    const approveWETHTx = await weth.approve(
      lendingMarket.address,
      "700000000000000" //Approve 0.07 tokens (worth 0.0007 eth) - audit
    );
    await approveWETHTx.wait();

    const createLiquidationAuctionTx =
      await lendingMarket.createLiquidationAuction(
        0,
        //"700000000000000", //Bid of 0.07 ETH
        "700000000000000", //Bid of 0.07 tokens (worth 0.0007 eth) - audit
        priceSig.request,
        priceSig
      );
    await createLiquidationAuctionTx.wait();
  });
  it("Claim the liquidation after the auction is over", async function () {
    // Make the auction end (24 hours)
    await ethers.provider.send("evm_increaseTime", [86401]);
    await ethers.provider.send("evm_mine", []);

    const claimTx = await lendingMarket.claimLiquidation(0);
    await claimTx.wait();

    // Find if the liquidator received the NFT
    expect(await testNFT.ownerOf(tokenID1)).to.equal(owner.address);
    expect(await testNFT.ownerOf(tokenID2)).to.equal(owner.address);
  });
});
