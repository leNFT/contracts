const { expect } = require("chai");
const load = require("../scripts/testDeploy/_loadTest.js");

describe("Deposit", function () {
  load.loadTest();
  var poolAddress;
  var tradingPool;
  it("Should create a pool and deposit into it", async function () {
    // Create a pool
    const createPoolTx = await tradingPoolFactory.createTradingPool(
      testNFT.address,
      weth.address
    );

    newPoolReceipt = await createPoolTx.wait();
    const event = newPoolReceipt.events.find(
      (event) => event.event === "CreateTradingPool"
    );
    poolAddress = event.args.pool;

    console.log("Created new pool: ", poolAddress);

    // Mint 50 test tokens to the callers address
    const mintTestNFTTx = await testNFT.mint(owner.address);
    await mintTestNFTTx.wait();

    // Deposit the tokens into the pool
    const TradingPool = await ethers.getContractFactory("TradingPool");
    tradingPool = TradingPool.attach(poolAddress);
    const approveNFTTx = await testNFT.setApprovalForAll(
      wethGateway.address,
      true
    );
    await approveNFTTx.wait();
    const depositTx = await wethGateway.depositTradingPool(
      poolAddress,
      0,
      [0],
      "100000000000000",
      exponentialCurve.address,
      "0",
      "100",
      { value: "100000000000000" }
    );
    await depositTx.wait();
  });
});
