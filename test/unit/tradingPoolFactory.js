const { expect } = require("chai");
const { ethers } = require("hardhat");
const { BigNumber } = require("ethers");
const load = require("../helpers/_loadTest.js");
const { getPriceSig } = require("../helpers/getPriceSig.js");

describe("TradingPoolFactory", function () {
  let TradingPoolFactory,
    tradingPoolFactory,
    owner,
    AddressProvider,
    addressProvider;

  beforeEach(async () => {
    AddressProvider = await ethers.getContractFactory("AddressesProvider");
    addressProvider = await upgrades.deployProxy(AddressProvider);
    TradingPoolFactory = await ethers.getContractFactory("TradingPoolFactory");
    [owner] = await ethers.getSigners();
    tradingPoolFactory = await upgrades.deployProxy(TradingPoolFactory, [
      addressProvider.address,
      "1000", // Default protocol fee (10%)
      "25000000000000000000", // TVLSafeguard
    ]);

    // Set the address in the address provider contract
    await addressProvider.setTradingPoolFactory(tradingPoolFactory.address);
  });

  it("Should be able to add a new price curve", async function () {
    // Deploy a new price curve
    const LinearCurve = await ethers.getContractFactory("LinearPriceCurve");
    const linearCurve = await LinearCurve.deploy();
    await linearCurve.deployed();

    expect(await tradingPoolFactory.isPriceCurve(linearCurve.address)).to.equal(
      false
    );

    // Add the price curve
    const tx = await tradingPoolFactory.setPriceCurve(
      linearCurve.address,
      true
    );
    await tx.wait();

    expect(await tradingPoolFactory.isPriceCurve(linearCurve.address)).to.equal(
      true
    );
  });
  it("Should be able to create a new trading pool", async function () {
    // Deploy the swap router contract & add it to address provider (needed for the trading pool creation)
    const SwapRouter = await ethers.getContractFactory("SwapRouter");
    const swapRouter = await SwapRouter.deploy(addressProvider.address);
    await swapRouter.deployed();
    await addressProvider.setSwapRouter(swapRouter.address);
    // Deploy a test token
    const TestToken = await ethers.getContractFactory("WETH");
    const testToken = await TestToken.deploy();

    // Deploy a test NFT
    const TestNFT = await ethers.getContractFactory("TestNFT");
    const testNFT = await TestNFT.deploy("Test NFT", "NFT");

    // There should be no trading pool for this token/NFT pair
    expect(
      await tradingPoolFactory.getTradingPool(
        testNFT.address,
        testToken.address
      )
    ).to.equal(ethers.constants.AddressZero);

    const tx = await tradingPoolFactory.createTradingPool(
      testNFT.address,
      testToken.address
    );
    await tx.wait();

    // There should now be a trading pool for this token/NFT pair
    const tradingPoolAddress = await tradingPoolFactory.getTradingPool(
      testNFT.address,
      testToken.address
    );
    expect(tradingPoolAddress).to.not.equal(ethers.constants.AddressZero);

    expect(await tradingPoolFactory.isTradingPool(tradingPoolAddress)).to.equal(
      true
    );
  });
});
