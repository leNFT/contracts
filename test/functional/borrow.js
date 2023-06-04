const { expect } = require("chai");
const { getPriceSig } = require("../helpers/getPriceSig.js");
const load = require("../helpers/_loadTest.js");

describe("Borrow", function () {
  load.loadTest(false);
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
      "800000000000000000", //Price of 80 ETH
      "1694784579",
      nftOracle.address
    );
    console.log("Got price sig for: ", [tokenID1, tokenID2]);
    // Ask the market to borrow underlying using the collateral
    const balanceBeforeBorrow = await owner.getBalance();
    console.log("Balance before borrow: ", balanceBeforeBorrow.toString());
    const borrowTx = await wethGateway.borrow(
      "1", // - audit
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
    //expect(
    //  balanceAfterBorrow.sub(balanceBeforeBorrow).add(gasUsedETH)
    //).to.be.eq("1000000000000000");

    // Find if the protocol received the asset
    expect(await testNFT.ownerOf(tokenID1)).to.equal(lendingMarket.address);
    expect(await testNFT.ownerOf(tokenID2)).to.equal(lendingMarket.address);
  });
  it("Repay borrowed amount", async function () {
    // Get loan debt
    const loanDebt = await loanCenter.getLoanDebt(0);

    const repayTx = await wethGateway.repay(0, {
      value: loanDebt,
    });
    await repayTx.wait();
    expect(await testNFT.ownerOf(tokenID1)).to.equal(owner.address);
    expect(await testNFT.ownerOf(tokenID2)).to.equal(owner.address);
  });
  // ------------------- audit ------------------------
  it("Second Borrow using NFT asset as collateral", async function () {
    // Approve assets to be used by the lending market
    const approveNftTx1 = await testNFT.approve(wethGateway.address, tokenID1);
    await approveNftTx1.wait();
    const approveNftTx2 = await testNFT.approve(wethGateway.address, tokenID2);
    await approveNftTx2.wait();

    const priceSig = getPriceSig(
      testNFT.address,
      [tokenID1, tokenID2],
      "800000000000000000", //Price of 80 ETH
      "1694784579",
      nftOracle.address
    );
    console.log("Got price sig for: ", [tokenID1, tokenID2]);
    // Ask the market to borrow underlying using the collateral
    const balanceBeforeBorrow = await owner.getBalance();
    console.log("Balance before borrow: ", balanceBeforeBorrow.toString());
    const borrowTx = await wethGateway.borrow(
      "100000000000000000", // - audit
      //"1000000000000000000"
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
    //expect(
    //  balanceAfterBorrow.sub(balanceBeforeBorrow).add(gasUsedETH)
    //).to.be.eq("1000000000000000");

    // Find if the protocol received the asset
    expect(await testNFT.ownerOf(tokenID1)).to.equal(lendingMarket.address);
    expect(await testNFT.ownerOf(tokenID2)).to.equal(lendingMarket.address);
  });
  it("Repay 1st borrowed amount again", async function () {
    // Get loan debt
    const loanDebt = await loanCenter.getLoanDebt(0);

    // Expect this transaction to revert since this was already repaid
    expect(
      wethGateway.repay(0, {
        value: loanDebt,
      })
    ).to.be.revertedWith("VL:VR:LOAN_NOT_FOUND");
  });
});
