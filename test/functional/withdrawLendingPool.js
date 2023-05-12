const { expect } = require("chai");
const load = require("../helpers/_loadTest.js");

describe("Withdraw from Lengin Pool", function () {
  load.loadTest();
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
  it("Should withdraw the underlying from the lending pool", async function () {
    // Approve assets to be used by the weth gateway
    const LendingPool = await ethers.getContractFactory("LendingPool", {
      libraries: {
        ValidationLogic: validationLogicLib.address,
      },
    });
    lendingPool = LendingPool.attach(
      await lendingMarket.getLendingPool(testNFT.address, weth.address)
    );
    const approveLpTx = await lendingPool.approve(
      wethGateway.address,
      "1000000000000000000"
    );
    await approveLpTx.wait();

    // Withdraw the tokens from the market
    const withdrawTx = await wethGateway.withdrawLendingPool(
      await lendingMarket.getLendingPool(testNFT.address, weth.address),
      "1000000000000000000"
    );
    await withdrawTx.wait();

    // Find if the lending pool tokens were sent accordingl
  });
});
