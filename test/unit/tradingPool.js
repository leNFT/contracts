const { expect } = require("chai");
const { ethers } = require("hardhat");
const { BigNumber } = require("ethers");
const load = require("../helpers/_loadTest.js");
const { getPriceSig } = require("../helpers/getPriceSig.js");

describe("TradingPool", function () {
  load.loadTestAlways(false);

  it("Should fail to directly create a new trading pool", async function () {
    const TradingPool = await ethers.getContractFactory("TradingPool");

    // Should fail on deployment from non-tradingPoolFactory address
    await expect(
      TradingPool.deploy(
        addressesProvider.address,
        owner.address,
        weth.address,
        testNFT.address,
        "Trading Pool Token",
        "TPT"
      )
    ).to.be.revertedWith("TP:C:MUST_BE_FACTORY");
  });
  it("Should get the correct token URI", async function () {
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

    const mintTestNFTTx = await testNFT.mint(owner.address);
    await mintTestNFTTx.wait();

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
      [0],
      "100000000000000",
      "100000000000000",
      exponentialCurve.address,
      "50",
      "500"
    );
    await depositTx.wait();

    // Get the token URI from the metadata contract
    const tokenURIMetadata = await liquidityPairMetadata.tokenURI(
      tradingPool.address,
      0
    );

    // Get the token URI from the trading pool
    const tokenURI = await tradingPool.tokenURI(0);

    // Compare the two and expect them to be equal
    expect(tokenURI).to.equal(tokenURIMetadata);
  });
  it("Should be able to add liquidity to a trading pool", async function () {
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

    const mintTestNFTTx = await testNFT.mint(owner.address);
    await mintTestNFTTx.wait();

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
      [0],
      "100000000000000",
      "100000000000000",
      exponentialCurve.address,
      "50",
      "500"
    );
    await depositTx.wait();

    // the nft to lp funtion should point the nft to the lp
    expect(await tradingPool.nftToLp(0)).to.equal(0);

    // The lp count should be 1
    expect(await tradingPool.getLpCount()).to.equal(1);

    // Get the lp and compare its values
    const lp = await tradingPool.getLP(0);
    expect(lp.lpType).to.equal(0);
    expect(lp.nftIds).to.deep.equal([BigNumber.from(0)]);
    expect(lp.tokenAmount).to.equal("100000000000000");
    expect(lp.spotPrice).to.equal("100000000000000");
    expect(lp.curve).to.equal(exponentialCurve.address);
    expect(lp.delta).to.equal("50");
    expect(lp.fee).to.equal("500");
  });
  it("Should be able to remove liquidity from a trading pool", async function () {
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

    const mintTestNFTTx = await testNFT.mint(owner.address);
    await mintTestNFTTx.wait();

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
      [0],
      "100000000000000",
      "100000000000000",
      exponentialCurve.address,
      "50",
      "500"
    );
    await depositTx.wait();

    // Remove the liquidity
    const removeLiquidityTx = await tradingPool.removeLiquidity(0);
    await removeLiquidityTx.wait();

    // The lp count should be still be 1
    expect(await tradingPool.getLpCount()).to.equal(1);

    // Should throw an error when trying to get the lp
    await expect(tradingPool.getLP(0)).to.be.revertedWith("TP:LP_NOT_FOUND");
  });
  it("Should be able to remove liquidity from a trading pool in batch", async function () {
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
    const mintTestTokenTx = await weth.deposit({ value: "200000000000000" });
    await mintTestTokenTx.wait();
    // Deposit the tokens into the market
    const approveTokenTx = await weth.approve(
      tradingPool.address,
      "200000000000000"
    );
    await approveTokenTx.wait();
    const depositTx1 = await tradingPool.addLiquidity(
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
    const depositTx2 = await tradingPool.addLiquidity(
      owner.address,
      0,
      [1],
      "100000000000000",
      "100000000000000",
      exponentialCurve.address,
      "50",
      "500"
    );
    await depositTx2.wait();

    // Remove the liquidity
    const removeLiquidityBatchTx = await tradingPool.removeLiquidityBatch([
      0, 1,
    ]);
    await removeLiquidityBatchTx.wait();

    // The lp count should be still be 2
    expect(await tradingPool.getLpCount()).to.equal(2);

    // Should throw an error when trying to get the lps
    await expect(tradingPool.getLP(0)).to.be.revertedWith("TP:LP_NOT_FOUND");
    await expect(tradingPool.getLP(1)).to.be.revertedWith("TP:LP_NOT_FOUND");
  });
  it("Should be able to buy one token", async function () {
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

    const mintTestNFTTx = await testNFT.mint(owner.address);
    await mintTestNFTTx.wait();

    const approveNFTTx = await testNFT.setApprovalForAll(
      tradingPool.address,
      true
    );
    await approveNFTTx.wait();
    // Mint and approve test tokens to the callers address
    const mintTestTokenTx = await weth.deposit({ value: "205000000000000" });
    await mintTestTokenTx.wait();
    // Deposit the tokens into the market
    const approveTokenTx = await weth.approve(
      tradingPool.address,
      "205000000000000"
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

    // Buy the tokens
    const buyTx = await tradingPool.buy(owner.address, [0], "105000000000000");
    await buyTx.wait();

    // Should now own both tokens
    expect(await testNFT.ownerOf(0)).to.equal(owner.address);

    // Get the lp
    const lp = await tradingPool.getLP(0);
    expect(lp.nftIds).to.deep.equal([]);
    expect(lp.tokenAmount).to.equal("204500000000000");
    expect(lp.spotPrice).to.equal("100500000000000");
  });
  it("Should be able to buy multiple tokens", async function () {
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

    // Buy the tokens
    const buyTx = await tradingPool.buy(
      owner.address,
      [0, 1],
      "210525000000000"
    );
    await buyTx.wait();

    // Should now own both tokens
    expect(await testNFT.ownerOf(0)).to.equal(owner.address);
    expect(await testNFT.ownerOf(1)).to.equal(owner.address);

    // Get the lp
    const lp = await tradingPool.getLP(0);
    expect(lp.nftIds).to.deep.equal([]);
    expect(lp.tokenAmount).to.equal("309522500000000");
    expect(lp.spotPrice).to.equal("101002500000000");
  });
  it("Should be able to sell one token", async function () {
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

    const mintTestNFTTx = await testNFT.mint(owner.address);
    await mintTestNFTTx.wait();

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

    // Buy the tokens
    const sellTx = await tradingPool.sell(
      owner.address,
      [0],
      [0],
      "47500000000000"
    );
    await sellTx.wait();

    // Should now own both tokens
    expect(await testNFT.ownerOf(0)).to.equal(tradingPool.address);

    // Get the lp
    const lp = await tradingPool.getLP(0);
    expect(lp.nftIds).to.deep.equal([BigNumber.from(0)]);
    expect(lp.tokenAmount).to.equal("52250000000000");
    expect(lp.spotPrice).to.equal("49751243781094");
  });
  it("Should be able to sell multiple tokens", async function () {
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

    // Buy the tokens
    const sellTx = await tradingPool.sell(
      owner.address,
      [0, 1],
      [0, 0],
      "94763681592040"
    );
    await sellTx.wait();

    // Should now own both tokens
    expect(await testNFT.ownerOf(0)).to.equal(tradingPool.address);
    expect(await testNFT.ownerOf(1)).to.equal(tradingPool.address);

    // Get the lp
    const lp = await tradingPool.getLP(0);
    expect(lp.nftIds).to.deep.equal([BigNumber.from(0), BigNumber.from(1)]);
    expect(lp.tokenAmount).to.equal("4737562189055");
    expect(lp.spotPrice).to.equal("49503725155317");
  });
  it("Should be able to add liquidity to a paused pool", async function () {
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

    // Pause the pool
    const pauseTx = await tradingPool.setPause(true);
    await pauseTx.wait();

    // try to add liquidity should fail
    await expect(
      tradingPool.addLiquidity(
        owner.address,
        0,
        [],
        "100000000000000",
        "50000000000000",
        exponentialCurve.address,
        "50",
        "500"
      )
    ).to.be.revertedWith("TP:POOL_PAUSED");
  });
});