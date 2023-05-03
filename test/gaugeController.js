const { expect } = require("chai");
const load = require("./helpers/_loadTest.js");

describe("Trading Gauge", () => {
  load.loadTest();
  var poolAddress;
  var tradingPool;
  var gauge;
  it("Should create a pool", async function () {
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
  });
  it("Should create a gauge", async function () {
    const Gauge = await ethers.getContractFactory("TradingGauge");
    gauge = await Gauge.deploy(addressesProvider.address, poolAddress);
    await gauge.deployed();
    console.log("Gauge address: ", gauge.address);

    const setAddGaugeTx = await gaugeController.addGauge(gauge.address);
    await setAddGaugeTx.wait();
    console.log("Added Gauge to Gauge Controller.");
  });
  it("Should lock tokens", async function () {
    // Mint 10 native tokens to the callers address
    const mintNativeTokenTx = await nativeToken.mint(
      owner.address,
      "100000000000000000000"
    );
    await mintNativeTokenTx.wait();

    console.log("Minted tokens");

    // Approve tokens for use by the voting escrow contract
    const approveTokenTx = await nativeToken.approve(
      votingEscrow.address,
      "100000000000000000000"
    );
    await approveTokenTx.wait();

    //Lock 10 tokens for 100 days
    await votingEscrow.createLock(
      owner.address,
      "100000000000000000000",
      Math.floor(Date.now() / 1000) + 86400 * 100
    );
    console.log(Math.floor(Date.now() / 1000) + 86400 * 100);
  });
  it("Should vote for the created gauge", async function () {
    console.log("VOTING");
    // Use 50% of the locked tokens to vote for the gauge
    const voteTx = await gaugeController.vote(0, gauge.address, "5000");
    await voteTx.wait();
    console.log("Voted for gauge");

    // Let 10 hour pass
    await ethers.provider.send("evm_increaseTime", [10 * 3600]);
    // Mine a new block
    await ethers.provider.send("evm_mine", []);

    // Find if the user received the asset
    console.log(
      "Gauge weight: ",
      await gaugeController.getGaugeWeight(gauge.address)
    );
    console.log("Total weight: ", await gaugeController.getTotalWeight());
    console.log(
      "lockVoteWeightForGauge",
      await gaugeController.lockVoteWeightForGauge(0, gauge.address)
    );
    console.log("userVoteWeight: ", await gaugeController.lockVoteRatio(0));

    expect(
      await gaugeController.lockVoteWeightForGauge(0, gauge.address)
    ).to.not.equal("0");
    expect(await gaugeController.lockVoteRatio(0)).to.not.equal("0");
  });
  it("Should remove some voting power", async function () {
    // Use 50% of the locked tokens to vote for the gauge
    const voteTx = await gaugeController.vote(0, gauge.address, "0");
    await voteTx.wait();
    console.log("Removed voting power");

    expect(
      await gaugeController.lockVoteWeightForGauge(0, gauge.address)
    ).to.equal("0");
    expect(await gaugeController.lockVoteRatio(0)).to.equal("0");
  });
});
