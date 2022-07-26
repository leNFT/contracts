const { expect } = require("chai");
const load = require("../scripts/testDeploy/_loadTest.js");

describe("Deposit", function () {
  load.loadTest();
  it("Should get reserve tokens when depositing into the reserve", async function () {
    // Mint 50 test tokens to the callers address
    const mintTestTokenTx = await testToken.mint(owner.address, 50);
    await mintTestTokenTx.wait();

    // Deposit the tokens into the market
    const approveTokenTx = await testToken.approve(testReserve.address, 50);
    await approveTokenTx.wait();
    const depositTx = await market.deposit(testToken.address, 50);
    await depositTx.wait();

    // Find if the reserve tokens were sent accordingly
    expect(await testReserve.getUnderlyingBalance()).to.equal(50);
    expect(await testReserve.balanceOf(owner.address)).to.equal(50);
  });
  it("Should get a proportinal amount of reserve tokens when depositing into the reserve", async function () {
    // Mint 50 test tokens to the callers address
    const mintTestTokenTx = await testToken.mint(owner.address, 50);
    await mintTestTokenTx.wait();

    // Deposit the tokens into the market
    const approveTokenTx = await testToken.approve(testReserve.address, 50);
    await approveTokenTx.wait();
    const depositTx = await market.deposit(testToken.address, 50);
    await depositTx.wait();

    // Find if the reserve tokens were sent accordingly
    expect(await testReserve.getUnderlyingBalance()).to.equal(100);
    expect(await testReserve.balanceOf(owner.address)).to.equal(100);
  });
  it("Should get a proportinal amount of reserve tokens when depositing into the an active reserve", async function () {
    // Mint 200 test tokens to the callers address
    const mintTestTokenTx = await testToken.mint(owner.address, 200);
    await mintTestTokenTx.wait();

    //Mint 100 tokens directly into the reserve
    const mintTestTokenReserveTx = await testToken.mint(
      testReserve.address,
      100
    );
    await mintTestTokenReserveTx.wait();

    // Deposit 200 tokens into the market
    const approveTokenTx = await testToken.approve(testReserve.address, 200);
    await approveTokenTx.wait();
    const depositTx = await market.deposit(testToken.address, 200);
    await depositTx.wait();

    // Find if the reserve tokens were sent accordingly
    expect(await testReserve.getUnderlyingBalance()).to.equal(400);
    expect(await testReserve.totalSupply()).to.equal(200);
    expect(await testReserve.balanceOf(owner.address)).to.equal(200);
  });
});
