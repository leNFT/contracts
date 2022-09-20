const { expect } = require("chai");
const { getPriceSig } = require("./helpers/getPriceSig.js");
const load = require("../scripts/testDeploy/_loadTest.js");

describe("Boost", function () {
  this.timeout(10000);
  load.loadTest();
  var tokenID;

  it("Create a loan", async function () {
    // Mint NFT collateral
    const mintTestNftTx = await testNFT.mint(owner.address);
    const tokenIDReceipt = await mintTestNftTx.wait();
    const event = tokenIDReceipt.events.find((event) => event.event === "Mint");
    tokenID = event.args.tokenId.toNumber();

    // Find if the NFT was minted accordingly
    expect(await testNFT.ownerOf(tokenID)).to.equal(owner.address);

    // Mint 100 test tokens to the callers address
    const mintTestTokenTx = await testToken.mint(owner.address, 200);
    await mintTestTokenTx.wait();

    // Deposit the tokens into the market
    const approveTokenTx = await testToken.approve(testReserve.address, 200);
    await approveTokenTx.wait();
    const depositTx = await market.deposit(testToken.address, 200);
    await depositTx.wait();

    // Find if the reserve tokens were sent accordingly
    expect(await testReserve.balanceOf(owner.address)).to.equal(200);
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
      testToken.address,
      50,
      testNFT.address,
      tokenID,
      priceSig.request,
      priceSig
    );
    await borrowTx.wait();

    // Find if the borrower received the funds
    expect(await testToken.balanceOf(owner.address)).to.equal(50);

    // Find if the protocol received the asset
    expect(await testNFT.ownerOf(tokenID)).to.equal(loanCenter.address);

    // Find if the utilization rate was changed accordingly
    expect(await testReserve.getUtilizationRate()).to.equal(2500);

    //Find if the supply rate has changed accordingly
    expect(await testReserve.getSupplyRate()).to.equal(250);
  });
  it("Vote for a collection", async function () {
    // Mint 100 native tokens to the callers address
    const mintNativeTokenTx = await nativeToken.mint(owner.address, 100);
    await mintNativeTokenTx.wait();

    // Deposit native token into the vault
    const approveNativeTokenTx = await nativeToken.approve(
      nativeTokenVault.address,
      100
    );
    await approveNativeTokenTx.wait();
    const depositNativeTokenTx = await nativeTokenVault.deposit(100);
    await depositNativeTokenTx.wait();

    //Vote for the test collection with the deposited tokens
    const voteTx = await nativeTokenVault.vote(100, testNFT.address);
    await voteTx.wait();

    //Find if the vote count has changed accordingly
    expect(
      await nativeTokenVault.getUserCollectionVotes(
        owner.address,
        testNFT.address
      )
    ).to.equal(100);

    //Find if the collection ltv boost has changed accordingly
    expect(
      await nativeTokenVault.getVoteCollateralizationBoost(
        owner.address,
        testNFT.address
      )
    ).to.equal(200);
  });
});
