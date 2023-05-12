const { expect } = require("chai");
const load = require("../helpers/_loadTest.js");

describe("Swap Router", () => {
  load.loadTest();
  var sellPoolAddress;
  var buyPoolAddress;

  it("Should create a test nft 1 pool and deposit into it", async function () {
    // Create a pool
    const createPoolTx = await tradingPoolFactory.createTradingPool(
      testNFT.address,
      weth.address
    );

    newPoolReceipt = await createPoolTx.wait();
    const event = newPoolReceipt.events.find(
      (event) => event.event === "CreateTradingPool"
    );
    sellPoolAddress = event.args.pool;

    console.log("Created new pool: ", sellPoolAddress);

    const mintTestNFTTx = await testNFT.mint(owner.address);
    await mintTestNFTTx.wait();

    // Deposit the tokens into the pool
    const TradingPool = await ethers.getContractFactory("TradingPool");
    tradingPool = TradingPool.attach(sellPoolAddress);
    const approveNFTTx = await testNFT.setApprovalForAll(sellPoolAddress, true);
    await approveNFTTx.wait();
    // Mint and approve test tokens to the callers address
    const mintTestTokenTx = await weth.deposit({ value: "100000000000000" });
    await mintTestTokenTx.wait();
    // Deposit the tokens into the market
    const approveTokenTx = await weth.approve(
      sellPoolAddress,
      "100000000000000"
    );
    await approveTokenTx.wait();
    const depositTx = await tradingPool.addLiquidity(
      owner.address,
      0,
      [0],
      "100000000000000",
      "100000000000000",
      exponentialCurve.address,
      "50",
      "500"
    );
    await depositTx.wait();

    // Find if the liquidator received the asset
    expect(await testNFT.ownerOf(0)).to.equal(sellPoolAddress);
  });

  it("Should create a test nft 2 pool and deposit into it", async function () {
    // Create a pool
    const createPoolTx = await tradingPoolFactory.createTradingPool(
      testNFT2.address,
      weth.address
    );

    newPoolReceipt = await createPoolTx.wait();
    const event = newPoolReceipt.events.find(
      (event) => event.event === "CreateTradingPool"
    );
    buyPoolAddress = event.args.pool;

    console.log("Created new pool: ", buyPoolAddress);

    // Mint 50 test tokens to the callers address
    const mintTestNFTTx = await testNFT2.mint(owner.address);
    await mintTestNFTTx.wait();

    // Deposit the tokens into the pool
    const TradingPool = await ethers.getContractFactory("TradingPool");
    tradingPool = TradingPool.attach(buyPoolAddress);
    const approveNFTTx = await testNFT2.setApprovalForAll(buyPoolAddress, true);
    await approveNFTTx.wait();
    // Mint and approve test tokens to the callers address
    const mintTestTokenTx = await weth.deposit({ value: "100000000000000" });
    await mintTestTokenTx.wait();
    // Deposit the tokens into the market
    const approveTokenTx = await weth.approve(
      buyPoolAddress,
      "100000000000000"
    );
    await approveTokenTx.wait();
    const depositTx = await tradingPool.addLiquidity(
      owner.address,
      0,
      [0],
      "100000000000000",
      "100000000000000",
      exponentialCurve.address,
      "50",
      "500"
    );
    await depositTx.wait();
  });

  it("Should swap nft 1 for nft 2", async function () {
    // MInt a token to swap
    const mintTestNFTTx = await testNFT.mint(owner.address);
    await mintTestNFTTx.wait();

    // Approve the token to be swapped
    const approveNFTTx = await testNFT.setApprovalForAll(
      wethGateway.address,
      true
    );
    await approveNFTTx.wait();

    const swapTx = await wethGateway.swap(
      buyPoolAddress,
      sellPoolAddress,
      [0],
      "200000000000000",
      [1],
      [0],
      "50000000000000",
      {
        value: 200000000000000 - 50000000000000,
      }
    );
    await swapTx.wait();

    expect(await testNFT2.ownerOf(0)).to.equal(owner.address);
  });
});
