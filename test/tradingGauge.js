const { expect } = require("chai");
const load = require("../scripts/testDeploy/_loadTest.js");

describe("Trading Gauge", () => {
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
    const approveNFTTx = await testNFT.setApprovalForAll(poolAddress, true);
    await approveNFTTx.wait();
    const depositTx = await tradingPool.addLiquidity(
      0,
      [0],
      owner.address,
      "0",
      "0"
    );
    await depositTx.wait();
  });
  it("Should create a gauge a stake into it", async function () {
    const Gauge = await ethers.getContractFactory("TradingGauge");
    const gauge = await Gauge.deploy(addressesProvider.address, poolAddress);
    await gauge.deployed();
    console.log("Gauge address: ", gauge.address);

    const setAddGaugeTx = await gaugeController.addGauge(gauge.address);
    await setAddGaugeTx.wait();
    console.log("Added Gauge to Gauge Controller.");

    // Approve NFT tx
    const approveNFTTx = await tradingPool.setApprovalForAll(
      gauge.address,
      true
    );
    await approveNFTTx.wait();

    // Deposit into gauge
    const depositInGaugeTx = await gauge.deposit(0);
    await depositInGaugeTx.wait();
    console.log("DEposited LP 0 in gauge");
  });
});
