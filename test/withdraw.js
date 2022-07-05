const { expect } = require("chai");
const load = require("../scripts/_load");

describe("Withdraw", function () {
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
});
