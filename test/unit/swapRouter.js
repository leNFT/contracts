const { expect } = require("chai");
const load = require("../helpers/_loadTest.js");
const { ethers } = require("hardhat");

describe("SwapRouter", () => {
  load.loadTest(false);
  var sellPoolAddress;
  var buyPoolAddress;

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

  it("Should swap between two assets for the exact predicted price", async function () {
    // Create a pool
    const createPoolTx1 = await tradingPoolFactory.createTradingPool(
      testNFT.address,
      weth.address
    );

    newPoolReceipt = await createPoolTx1.wait();
    const event1 = newPoolReceipt.events.find(
      (event1) => event1.event === "CreateTradingPool"
    );
    sellPoolAddress = event1.args.pool;

    console.log("Created new pool: ", sellPoolAddress);

    const mintTestNFTTx1 = await testNFT.mint(owner.address);
    await mintTestNFTTx1.wait();

    // Deposit the tokens into the pool
    const TradingPool1 = await ethers.getContractFactory("TradingPool");
    tradingPool1 = TradingPool1.attach(sellPoolAddress);
    const approveNFTTx1 = await testNFT.setApprovalForAll(
      sellPoolAddress,
      true
    );
    await approveNFTTx1.wait();
    // Mint and approve test tokens to the callers address
    const mintTestTokenTx1 = await weth.deposit({ value: "100000000000000" });
    await mintTestTokenTx1.wait();
    // Deposit the tokens into the market
    const approveTokenTx1 = await weth.approve(
      sellPoolAddress,
      "100000000000000"
    );
    await approveTokenTx1.wait();
    const depositTx1 = await tradingPool1.addLiquidity(
      owner.address,
      0,
      [0],
      "100000000000000",
      "100000000000000",
      exponentialCurve.address,
      "50",
      "500"
    );
    await depositTx1.wait();

    // Create a pool
    const createPoolTx2 = await tradingPoolFactory.createTradingPool(
      testNFT2.address,
      weth.address
    );

    newPoolReceipt = await createPoolTx2.wait();
    const event2 = newPoolReceipt.events.find(
      (event2) => event2.event === "CreateTradingPool"
    );
    buyPoolAddress = event2.args.pool;

    console.log("Created new pool: ", buyPoolAddress);

    // Mint 50 test tokens to the callers address
    const mintTestNFTTx2 = await testNFT2.mint(owner.address);
    await mintTestNFTTx2.wait();

    // Deposit the tokens into the pool
    const TradingPool2 = await ethers.getContractFactory("TradingPool");
    tradingPool2 = TradingPool2.attach(buyPoolAddress);
    const approveNFTTx2 = await testNFT2.setApprovalForAll(
      buyPoolAddress,
      true
    );
    await approveNFTTx2.wait();
    // Mint and approve test tokens to the callers address
    const mintTestTokenTx2 = await weth.deposit({ value: "100000000000000" });
    await mintTestTokenTx2.wait();
    // Deposit the tokens into the market
    const approveTokenTx2 = await weth.approve(
      buyPoolAddress,
      "100000000000000"
    );
    await approveTokenTx2.wait();
    const depositTx2 = await tradingPool2.addLiquidity(
      owner.address,
      0,
      [0],
      "100000000000000",
      "100000000000000",
      exponentialCurve.address,
      "50",
      "500"
    );
    await depositTx2.wait();

    // MInt a token to swap
    const mintTestNFTTx3 = await testNFT.mint(owner.address);
    await mintTestNFTTx3.wait();

    // Approve the token to be swapped
    const approveNFTTx3 = await testNFT.setApprovalForAll(
      wethGateway.address,
      true
    );
    await approveNFTTx3.wait();

    // Deposit some ETH to swap and make sure we have 0 tokens
    expect(await weth.balanceOf(owner.address)).to.equal("0");
    const mintTestTokenTx3 = await weth.deposit({
      value: "10000000000000",
    });
    await mintTestTokenTx3.wait();

    // Approve the weth to be swapped
    const approveTokenTx3 = await weth.approve(
      swapRouter.address,
      ethers.constants.MaxUint256
    );
    await approveTokenTx3.wait();

    const swapTx = await swapRouter.swap(
      buyPoolAddress,
      sellPoolAddress,
      [0],
      "105000000000000", // effective price will be 105000000000000
      [1],
      [0],
      "95000000000000" // effective price will be 95000000000000
    );
    await swapTx.wait();

    expect(await testNFT2.ownerOf(0)).to.equal(owner.address);
    expect(await testNFT.ownerOf(0)).to.equal(sellPoolAddress);
    expect(await weth.balanceOf(owner.address)).to.equal("0");
  });
  it("Should swap between two assets and get change back", async function () {
    // Create a pool
    const createPoolTx1 = await tradingPoolFactory.createTradingPool(
      testNFT.address,
      weth.address
    );

    newPoolReceipt = await createPoolTx1.wait();
    const event1 = newPoolReceipt.events.find(
      (event1) => event1.event === "CreateTradingPool"
    );
    sellPoolAddress = event1.args.pool;

    console.log("Created new pool: ", sellPoolAddress);

    const mintTestNFTTx1 = await testNFT.mint(owner.address);
    await mintTestNFTTx1.wait();

    // Deposit the tokens into the pool
    const TradingPool1 = await ethers.getContractFactory("TradingPool");
    tradingPool1 = TradingPool1.attach(sellPoolAddress);
    const approveNFTTx1 = await testNFT.setApprovalForAll(
      sellPoolAddress,
      true
    );
    await approveNFTTx1.wait();
    // Mint and approve test tokens to the callers address
    const mintTestTokenTx1 = await weth.deposit({ value: "100000000000000" });
    await mintTestTokenTx1.wait();
    // Deposit the tokens into the market
    const approveTokenTx1 = await weth.approve(
      sellPoolAddress,
      "100000000000000"
    );
    await approveTokenTx1.wait();
    const depositTx1 = await tradingPool1.addLiquidity(
      owner.address,
      0,
      [0],
      "100000000000000",
      "100000000000000",
      exponentialCurve.address,
      "50",
      "500"
    );
    await depositTx1.wait();

    // Create a pool
    const createPoolTx2 = await tradingPoolFactory.createTradingPool(
      testNFT2.address,
      weth.address
    );

    newPoolReceipt = await createPoolTx2.wait();
    const event2 = newPoolReceipt.events.find(
      (event2) => event2.event === "CreateTradingPool"
    );
    buyPoolAddress = event2.args.pool;

    console.log("Created new pool: ", buyPoolAddress);

    // Mint 50 test tokens to the callers address
    const mintTestNFTTx2 = await testNFT2.mint(owner.address);
    await mintTestNFTTx2.wait();

    // Deposit the tokens into the pool
    const TradingPool2 = await ethers.getContractFactory("TradingPool");
    tradingPool2 = TradingPool2.attach(buyPoolAddress);
    const approveNFTTx2 = await testNFT2.setApprovalForAll(
      buyPoolAddress,
      true
    );
    await approveNFTTx2.wait();
    // Mint and approve test tokens to the callers address
    const mintTestTokenTx2 = await weth.deposit({ value: "100000000000000" });
    await mintTestTokenTx2.wait();
    // Deposit the tokens into the market
    const approveTokenTx2 = await weth.approve(
      buyPoolAddress,
      "100000000000000"
    );
    await approveTokenTx2.wait();
    const depositTx2 = await tradingPool2.addLiquidity(
      owner.address,
      0,
      [0],
      "100000000000000",
      "100000000000000",
      exponentialCurve.address,
      "50",
      "500"
    );
    await depositTx2.wait();

    // MInt a token to swap
    const mintTestNFTTx3 = await testNFT.mint(owner.address);
    await mintTestNFTTx3.wait();

    // Approve the token to be swapped
    const approveNFTTx3 = await testNFT.setApprovalForAll(
      wethGateway.address,
      true
    );
    await approveNFTTx3.wait();

    // Deposit some ETH to swap and make sure we have 0 tokens
    expect(await weth.balanceOf(owner.address)).to.equal("0");
    const mintTestTokenTx3 = await weth.deposit({
      value: "20000000000000",
    });
    await mintTestTokenTx3.wait();

    // Approve the weth to be swapped
    const approveTokenTx3 = await weth.approve(
      swapRouter.address,
      ethers.constants.MaxUint256
    );
    await approveTokenTx3.wait();

    const swapTx = await swapRouter.swap(
      buyPoolAddress,
      sellPoolAddress,
      [0],
      "110000000000000", // effective price will be 105000000000000
      [1],
      [0],
      "90000000000000" // effective price will be 95000000000000
    );
    await swapTx.wait();

    expect(await testNFT2.ownerOf(0)).to.equal(owner.address);
    expect(await testNFT.ownerOf(0)).to.equal(sellPoolAddress);
    expect(await weth.balanceOf(owner.address)).to.equal("10000000000000");
  });
});
