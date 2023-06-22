const { expect } = require("chai");
const { ethers } = require("hardhat");
const { BigNumber } = require("ethers");

describe("TradingPoolFactory", function () {
  let TradingPoolFactory,
    tradingPoolFactory,
    owner,
    AddressProvider,
    addressProvider;

  before(async () => {
    AddressProvider = await ethers.getContractFactory("AddressProvider");
    addressProvider = await upgrades.deployProxy(AddressProvider);
    TradingPoolFactory = await ethers.getContractFactory("TradingPoolFactory");
    [owner] = await ethers.getSigners();
    tradingPoolFactory = await upgrades.deployProxy(
      TradingPoolFactory,
      [
        "1000", // Default protocol fee (10%)
        "25000000000000000000", // TVLSafeguard
      ],
      {
        unsafeAllow: ["state-variable-immutable"],
        constructorArgs: [addressProvider.address],
      }
    );

    // Set the address in the address provider contract
    await addressProvider.setTradingPoolFactory(tradingPoolFactory.address);

    // Take a snapshot before the tests start
    snapshotId = await ethers.provider.send("evm_snapshot", []);
  });

  beforeEach(async function () {
    // Restore the blockchain state to the snapshot before each test
    await ethers.provider.send("evm_revert", [snapshotId]);

    // Take a snapshot before the tests start
    snapshotId = await ethers.provider.send("evm_snapshot", []);
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
  it("Should be able to set a trading pool", async function () {
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

    // Remove the trading pool
    const tx2 = await tradingPoolFactory.setTradingPool(
      testNFT.address,
      testToken.address,
      ethers.constants.AddressZero
    );
    await tx2.wait();

    // There should now be no trading pool for this token/NFT pair
    expect(
      await tradingPoolFactory.getTradingPool(
        testNFT.address,
        testToken.address
      )
    ).to.equal(ethers.constants.AddressZero);

    // Set the trading pool again
    const tx3 = await tradingPoolFactory.setTradingPool(
      testNFT.address,
      testToken.address,
      tradingPoolAddress
    );
    await tx3.wait();

    // There should now be a trading pool for this token/NFT pair
    expect(
      await tradingPoolFactory.getTradingPool(
        testNFT.address,
        testToken.address
      )
    ).to.equal(tradingPoolAddress);
  });
  it("Should be able to set the tvl safeguard", async function () {
    // set the tvl safeguard
    const tx = await tradingPoolFactory.setTVLSafeguard(
      ethers.utils.parseEther("100")
    );
    await tx.wait();

    // check the tvl safeguard
    expect(await tradingPoolFactory.getTVLSafeguard()).to.equal(
      ethers.utils.parseEther("100")
    );
  });
  it("Should be able to set the protocol fee percentage", async function () {
    // set the protocol fee percentage
    const tx = await tradingPoolFactory.setProtocolFeePercentage(
      3000 // 30%
    );
    await tx.wait();

    // check the protocol fee percentage
    expect(await tradingPoolFactory.getProtocolFeePercentage()).to.equal(3000);
  });
});
