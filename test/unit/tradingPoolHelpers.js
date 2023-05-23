const { expect } = require("chai");
const { ethers } = require("hardhat");
const { BigNumber } = require("ethers");
const load = require("../helpers/_loadTest.js");

describe("TradingPoolHelpers", function () {
  load.loadTest(false);

  before(async function () {
    // Take a snapshot before the tests start
    snapshotId = await ethers.provider.send("evm_snapshot", []);
  });

  beforeEach(async function () {
    // Restore the blockchain state to the snapshot before each test
    await ethers.provider.send("evm_revert", [snapshotId]);

    // Take a snapshot before the tests start
    snapshotId = await ethers.provider.send("evm_snapshot", []);
  });

  it("Should get the right buy quote", async function () {
    // Create a new trading pool
    const createPoolTx = await tradingPoolFactory.createTradingPool(
      testNFT.address,
      weth.address
    );
    createPoolTx.wait();

    const tradingPool = await ethers.getContractAt(
      "TradingPool",
      await tradingPoolFactory.getTradingPool(testNFT.address, weth.address)
    );

    const mintTestNFTTx1 = await testNFT.mint(owner.address);
    await mintTestNFTTx1.wait();
    const mintTestNFTTx2 = await testNFT.mint(owner.address);
    await mintTestNFTTx2.wait();

    const approveNFTTx = await testNFT.setApprovalForAll(
      tradingPool.address,
      true
    );
    await approveNFTTx.wait();
    // Mint and approve test tokens to the callers address
    const mintTestTokenTx = await weth.deposit({ value: "310525000000000" });
    await mintTestTokenTx.wait();
    // Deposit the tokens into the market
    const approveTokenTx = await weth.approve(
      tradingPool.address,
      "310525000000000"
    );
    await approveTokenTx.wait();
    const depositTx = await tradingPool.addLiquidity(
      owner.address,
      0,
      [0, 1],
      "100000000000000",
      "100000000000000",
      exponentialCurve.address,
      "50",
      "500"
    );
    await depositTx.wait();

    // Get the users balance before the buy
    const balanceBefore = await weth.balanceOf(owner.address);

    // Get the buy quote
    const buyQuote = await tradingPoolHelpers.simulateBuy(
      tradingPool.address,
      [0, 1]
    );

    // Buy the tokens
    const buyTx = await tradingPool.buy(owner.address, [0, 1], buyQuote);
    await buyTx.wait();

    // The balance after the buy should be the same as the balance before the buy minus the buy quote
    expect(await weth.balanceOf(owner.address)).to.equal(
      balanceBefore.sub(buyQuote)
    );
  });

  it("Should get the right sell quote", async function () {
    // Create a new trading pool
    const createPoolTx = await tradingPoolFactory.createTradingPool(
      testNFT.address,
      weth.address
    );
    createPoolTx.wait();

    const tradingPool = await ethers.getContractAt(
      "TradingPool",
      await tradingPoolFactory.getTradingPool(testNFT.address, weth.address)
    );

    const mintTestNFTTx1 = await testNFT.mint(owner.address);
    await mintTestNFTTx1.wait();
    const mintTestNFTTx2 = await testNFT.mint(owner.address);
    await mintTestNFTTx2.wait();

    const approveNFTTx = await testNFT.setApprovalForAll(
      tradingPool.address,
      true
    );
    await approveNFTTx.wait();
    // Mint and approve test tokens to the callers address
    const mintTestTokenTx = await weth.deposit({ value: "100000000000000" });
    await mintTestTokenTx.wait();
    // Deposit the tokens into the market
    const approveTokenTx = await weth.approve(
      tradingPool.address,
      "100000000000000"
    );
    await approveTokenTx.wait();
    const depositTx = await tradingPool.addLiquidity(
      owner.address,
      0,
      [],
      "100000000000000",
      "50000000000000",
      exponentialCurve.address,
      "50",
      "500"
    );
    await depositTx.wait();

    const sellQuote = await tradingPoolHelpers.simulateSell(
      tradingPool.address,
      [0, 1],
      [0, 0]
    );

    // Get the users balance before the sell
    const balanceBefore = await weth.balanceOf(owner.address);

    // Sell the tokens
    const sellTx = await tradingPool.sell(
      owner.address,
      [0, 1],
      [0, 0],
      "94763681592040"
    );
    await sellTx.wait();

    expect(await weth.balanceOf(owner.address)).to.equal(
      balanceBefore.add(sellQuote)
    );
  });
  it("Should get the right liquidity pair to sell into", async function () {
    // Create a new trading pool
    const createPoolTx = await tradingPoolFactory.createTradingPool(
      testNFT.address,
      weth.address
    );
    createPoolTx.wait();

    const tradingPool = await ethers.getContractAt(
      "TradingPool",
      await tradingPoolFactory.getTradingPool(testNFT.address, weth.address)
    );

    // Mint and approve test tokens to the callers address
    const mintTestTokenTx = await weth.deposit({
      value: ethers.utils.parseEther("5"),
    });
    await mintTestTokenTx.wait();
    // Deposit the tokens into the market
    const approveTokenTx = await weth.approve(
      tradingPool.address,
      ethers.utils.parseEther("5")
    );
    await approveTokenTx.wait();
    const depositTx = await tradingPool.addLiquidity(
      owner.address,
      0,
      [],
      ethers.utils.parseEther("5"), // Amount of tokens to deposit
      ethers.utils.parseEther("1"), // Price of the NFTs
      exponentialCurve.address,
      "50",
      "500"
    );
    await depositTx.wait();

    const sellLps = await tradingPoolHelpers.getSellLiquidityPairs(
      tradingPool.address,
      1
    );

    // Should give the correct liquidity pairs
    expect(sellLps).to.deep.equal([BigNumber.from(0)]);
  });
  it("Should get the right liquidity pairs to sell into", async function () {
    // Create a new trading pool
    const createPoolTx = await tradingPoolFactory.createTradingPool(
      testNFT.address,
      weth.address
    );
    createPoolTx.wait();

    const tradingPool = await ethers.getContractAt(
      "TradingPool",
      await tradingPoolFactory.getTradingPool(testNFT.address, weth.address)
    );

    // Mint and approve test tokens to the callers address
    const mintTestTokenTx = await weth.deposit({
      value: ethers.utils.parseEther("1"),
    });
    await mintTestTokenTx.wait();
    // Deposit the tokens into the market
    const approveTokenTx = await weth.approve(
      tradingPool.address,
      ethers.utils.parseEther("1")
    );
    await approveTokenTx.wait();
    const depositTx = await tradingPool.addLiquidity(
      owner.address,
      0,
      [],
      ethers.utils.parseEther("1"), // Amount of tokens to deposit
      ethers.utils.parseEther("5"), // Price of the NFTs
      exponentialCurve.address,
      "50",
      "500"
    );
    await depositTx.wait();

    // Mint and approve test tokens to the callers address
    const mintTestTokenTx2 = await weth.deposit({
      value: ethers.utils.parseEther("15"),
    });
    await mintTestTokenTx2.wait();
    // Deposit the tokens into the market
    const approveTokenTx2 = await weth.approve(
      tradingPool.address,
      ethers.utils.parseEther("15")
    );
    await approveTokenTx2.wait();
    const depositTx2 = await tradingPool.addLiquidity(
      owner.address,
      0,
      [],
      ethers.utils.parseEther("15"), // Amount of tokens to deposit
      ethers.utils.parseEther("5"), // Price of the NFTs
      exponentialCurve.address,
      "50",
      "500"
    );
    await depositTx2.wait();

    const sellLps = await tradingPoolHelpers.getSellLiquidityPairs(
      tradingPool.address,
      2
    );

    // Should give the correct liquidity pairs
    expect(sellLps).to.deep.equal([BigNumber.from(1), BigNumber.from(1)]);
  });
});
