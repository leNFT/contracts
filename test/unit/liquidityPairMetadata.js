const { expect } = require("chai");
const { time } = require("@nomicfoundation/hardhat-network-helpers");
const { ethers } = require("hardhat");
const { BigNumber } = require("ethers");
const load = require("../helpers/_loadTest.js");
const { getPriceSig, priceSigner } = require("../helpers/getPriceSig.js");
const { parse } = require("dotenv");
const { Liquidity } = require("@balancer-labs/sdk");
const parseSVG = require("svg-parser").parse;

const isValidJSON = (str) => {
  try {
    JSON.parse(str);
    return true;
  } catch (e) {
    console.log(e);
    return false;
  }
};

const isValidSVG = (str) => {
  try {
    parseSVG(str);
    return true;
  } catch (e) {
    console.error(e);
    return false;
  }
};

describe("LiquidityPairMetadata", function () {
  load.loadTestAlways(false);

  it("Should get a valid JSON token URI for a certain liquidity pair", async function () {
    // Create a new trading pool
    const createTradingPoolTx = await tradingPoolFactory.createTradingPool(
      testNFT.address,
      wethAddress
    );
    await createTradingPoolTx.wait();

    // Get the pool address
    const poolAddress = await tradingPoolFactory.getTradingPool(
      testNFT.address,
      wethAddress
    );
    const mintTestNFTTx = await testNFT.mint(owner.address);
    await mintTestNFTTx.wait();

    // Deposit the tokens into the pool
    const TradingPool = await ethers.getContractFactory("TradingPool");
    tradingPool = TradingPool.attach(poolAddress);
    const approveNFTTx = await testNFT.setApprovalForAll(poolAddress, true);
    await approveNFTTx.wait();
    // Mint and approve test tokens to the callers address
    const mintTestTokenTx = await weth.deposit({
      value: "100000000000000",
    });
    await mintTestTokenTx.wait();
    // Deposit the tokens into the market
    const approveTokenTx = await weth.approve(poolAddress, "100000000000000");
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

    const tokenURI = await liquidityPairMetadata.tokenURI(poolAddress, 0);
    const base64Data = tokenURI.split("base64,")[1]; // Extract the base64 content
    console.log(base64Data);
    const decodedDataBuffer = ethers.utils.base64.decode(base64Data);
    const decodedData = Buffer.from(decodedDataBuffer).toString("utf-8"); // Convert ArrayBuffer to a UTF-8 string using Buffer.from()

    expect(isValidJSON(decodedData)).to.be.true;
  });

  it("Should get a valid SVG", async function () {
    // Create a new trading pool
    const createTradingPoolTx = await tradingPoolFactory.createTradingPool(
      testNFT.address,
      wethAddress
    );
    await createTradingPoolTx.wait();

    // Get the pool address
    const poolAddress = await tradingPoolFactory.getTradingPool(
      testNFT.address,
      wethAddress
    );
    const mintTestNFTTx = await testNFT.mint(owner.address);
    await mintTestNFTTx.wait();

    // Deposit the tokens into the pool
    const TradingPool = await ethers.getContractFactory("TradingPool");
    tradingPool = TradingPool.attach(poolAddress);
    const approveNFTTx = await testNFT.setApprovalForAll(poolAddress, true);
    await approveNFTTx.wait();
    // Mint and approve test tokens to the callers address
    const mintTestTokenTx = await weth.deposit({
      value: "100000000000000",
    });
    await mintTestTokenTx.wait();
    // Deposit the tokens into the market
    const approveTokenTx = await weth.approve(poolAddress, "100000000000000");
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

    const tokenURI = await liquidityPairMetadata.svg(poolAddress, 0);
    const decodedData = ethers.utils.toUtf8String(tokenURI); // Convert the hex string to a UTF-8 string

    expect(isValidSVG(decodedData)).to.be.true;
  });
});