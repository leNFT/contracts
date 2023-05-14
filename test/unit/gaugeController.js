const { expect } = require("chai");
const load = require("../helpers/_loadTest.js");
const { ethers } = require("hardhat");

describe("GaugeController", () => {
  load.loadTestAlways(false);

  // Deploy one trading pool and one lending pool and their gauges
  beforeEach(async function () {
    // Create a new trading pool
    const createTradingPoolTx = await tradingPoolFactory.createTradingPool(
      testNFT.address,
      weth.address
    );
    createTradingPoolTx.wait();

    tradingPool = await ethers.getContractAt(
      "TradingPool",
      await tradingPoolFactory.getTradingPool(testNFT.address, weth.address)
    );

    // Create a new lending pool through the market
    const createTx = await lendingMarket.createLendingPool(
      testNFT.address,
      wethAddress
    );
    await createTx.wait();
    const lendingPoolAddress = await lendingMarket.getLendingPool(
      testNFT.address,
      wethAddress
    );
    lendingPool = await ethers.getContractAt("LendingPool", lendingPoolAddress);

    // Deploy a trading gauge
    const TradingGauge = await ethers.getContractFactory("TradingGauge");
    tradingGauge = await TradingGauge.deploy(
      addressesProvider.address,
      tradingPool.address
    );
    await tradingGauge.deployed();

    // Deploy a lending gauge
    const LendingGauge = await ethers.getContractFactory("LendingGauge");
    lendingGauge = await LendingGauge.deploy(
      addressesProvider.address,
      lendingPool.address
    );
    await lendingGauge.deployed();
  });

  //   it("Should be able to add a gauge", async function () {
  //     // Add a trading gauge
  //     expect(await gaugeController.isGauge(tradingGauge.address)).to.be.false;
  //     const addTradingGaugeTx = await gaugeController.addGauge(
  //       tradingGauge.address
  //     );
  //     await addTradingGaugeTx.wait();
  //     expect(await gaugeController.isGauge(tradingGauge.address)).to.be.true;

  //     expect(await gaugeController.getGauge(tradingPool.address)).to.equal(
  //       tradingGauge.address
  //     );

  //     // Add a lending gauge
  //     expect(await gaugeController.isGauge(lendingGauge.address)).to.be.false;
  //     const addLendingGaugeTx = await gaugeController.addGauge(
  //       lendingGauge.address
  //     );
  //     await addLendingGaugeTx.wait();
  //     expect(await gaugeController.getGauge(lendingPool.address)).to.equal(
  //       lendingGauge.address
  //     );
  //   });
  //   it("Should be able to remove a gauge", async function () {
  //     // Add a trading gauge
  //     const addTradingGaugeTx = await gaugeController.addGauge(
  //       tradingGauge.address
  //     );
  //     await addTradingGaugeTx.wait();
  //     expect(await gaugeController.isGauge(tradingGauge.address)).to.be.true;

  //     expect(await gaugeController.getGauge(tradingPool.address)).to.equal(
  //       tradingGauge.address
  //     );

  //     // Remove a trading gauge
  //     const removeGaugeTx = await gaugeController.removeGauge(
  //       tradingGauge.address
  //     );
  //     await removeGaugeTx.wait();

  //     expect(await gaugeController.isGauge(tradingGauge.address)).to.be.false;

  //     expect(await gaugeController.getGauge(tradingPool.address)).to.equal(
  //       ethers.constants.AddressZero
  //     );
  //   });
  //   it("Should get the rewards for an epoch", async function () {
  //     const epochRewardCeiling = await gaugeController.getRewardsCeiling(1);
  //     expect(epochRewardCeiling).to.equal("11666666666666666666");
  //   });
  it("Should get the current gauge weight", async function () {
    // MInt some LE to the callers address
    const mintTx = await nativeToken.mint(
      owner.address,
      ethers.utils.parseEther("1000000")
    );
    await mintTx.wait();
    // Create a lock with the LE
    const lockTx = await votingEscrow.createLock(
      owner.address,
      ethers.utils.parseEther("1000000"),
      Date.now() / 1000 + 3600 * 30 // 30 days
    );
    await lockTx.wait();
    // Add a trading gauge
    const addTradingGaugeTx = await gaugeController.addGauge(
      tradingGauge.address
    );
    await addTradingGaugeTx.wait();
    // Vote for the gauge with 50 % of the voting power of the lock
    const voteTx = await gaugeController.vote(0, tradingGauge.address, 5000);
    await voteTx.wait();

    // Get the gauge weight
    const gaugeWeight = await gaugeController.getGaugeWeight(
      tradingGauge.address
    );
    expect(gaugeWeight).to.equal(ethers.utils.parseEther("5000"));
  });
});
