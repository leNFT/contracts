const { expect } = require("chai");
const load = require("../scripts/testDeploy/_loadTest.js");

describe("Withdraw", function () {
  this.timeout(10000);
  load.loadTest();
  it("Deposit the underlying token to the reserve", async function () {
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
  it("Should withdraw the underlying token from the reserve", async function () {
    // Withdraw the tokens from the market
    const withdrawTx = await market.withdraw(testToken.address, 100);
    await withdrawTx.wait();

    // Find if the reserve tokens were sent accordingly
    expect(await testToken.balanceOf(owner.address)).to.equal(100);
  });
  it("Should proportionally withdraw the underlying token from the reserve", async function () {
    // Mint 200 test tokens to the callers address
    const mintTestTokenTx = await testToken.mint(owner.address, 200);
    await mintTestTokenTx.wait();

    // Deposit the tokens into the market
    const approveTokenTx = await testToken.approve(testReserve.address, 200);
    await approveTokenTx.wait();
    const depositTx = await market.deposit(testToken.address, 200);
    await depositTx.wait();

    // Withdraw 100 tokens from the market
    const withdrawTx = await market.withdraw(testToken.address, 100);
    await withdrawTx.wait();

    // Find if the reserve tokens were sent accordingly
    expect(await testToken.balanceOf(owner.address)).to.equal(200);
    expect(await testReserve.balanceOf(owner.address)).to.equal(100);
  });
  it("Should proportionally withdraw the underlying token from an active reserve", async function () {
    //Mint 100 tokens directly into the reserve
    const mintTestTokenReserveTx = await testToken.mint(
      testReserve.address,
      100
    );
    await mintTestTokenReserveTx.wait();

    // Check if maximum withdrawal is 200
    expect(
      await testReserve.getMaximumWithdrawalAmount(owner.address)
    ).to.equal(200);

    // Withdraw 200 tokens from the market
    const withdrawTx = await market.withdraw(testToken.address, 200);
    await withdrawTx.wait();

    // Find if the reserve tokens were sent accordingly
    expect(await testToken.balanceOf(owner.address)).to.equal(400);
    expect(await testReserve.balanceOf(owner.address)).to.equal(0);
  });
  it("Should throw an error when withdraw from an overused reserved", async function () {
    // Mint NFT collateral
    const mintTestNftTx = await testNFT.mint(owner.address);
    tokenIDReceipt = await mintTestNftTx.wait();
    const event = tokenIDReceipt.events.find((event) => event.event === "Mint");
    tokenID = event.args.tokenId.toNumber();
    // Approve asset to be used by the market
    const approveNftTx = await testNFT.approve(market.address, tokenID);
    await approveNftTx.wait();

    //Deposit more underlying into the reserve
    const approveTokenTx = await testToken.approve(testReserve.address, 200);
    await approveTokenTx.wait();
    const depositTx = await market.deposit(testToken.address, 200);
    await depositTx.wait();

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

    // Ask the market to borrow underlying using the collateral
    const borrowTx = await market.borrow(
      testToken.address,
      100,
      testNFT.address,
      tokenID,
      request,
      serverPacket
    );
    await borrowTx.wait();

    // Withdraw 200 tokens from the market
    await expect(market.withdraw(testToken.address, 90)).to.be.revertedWith(
      "Reserve utilization rate too high"
    );
  });
});
