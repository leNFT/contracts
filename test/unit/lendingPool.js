const { expect } = require("chai");
const { ethers } = require("hardhat");
const { BigNumber } = require("ethers");
const load = require("../helpers/_loadTest.js");
const { getPriceSig } = require("../helpers/getPriceSig.js");
const { time } = require("@nomicfoundation/hardhat-network-helpers");

describe("LendingPool", function () {
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

  it("Should fail to directly create a new lending pool", async function () {
    const LendingPool = await ethers.getContractFactory("LendingPool");

    // Should fail on deployment from non-market address
    await expect(
      LendingPool.deploy(
        addressProvider.address,
        owner.address,
        weth.address,
        "Lending Pool Token",
        "LPT",
        {
          maxLiquidatorDiscount: "2000", // maxLiquidatorDiscount
          auctioneerFeeRate: "50", // defaultauctioneerFee
          liquidationFeeRate: "200", // defaultProtocolLiquidationFee
          maxUtilizationRate: "8500", // defaultmaxUtilizationRate
        }
      )
    ).to.be.revertedWith("LP:C:ONLY_MARKET");
  });
  it("Returns the right number of decimals", async function () {
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
    const lendingPool = await ethers.getContractAt(
      "LendingPool",
      lendingPoolAddress
    );
    const decimals = await lendingPool.decimals();
    expect(decimals).to.equal(18);
  });
  it("Deposits into the pool", async function () {
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
    const lendingPool = await ethers.getContractAt(
      "LendingPool",
      lendingPoolAddress
    );

    // Deposit into weth contract
    const depositTx = await weth.deposit({
      value: ethers.utils.parseEther("1"),
    });
    await depositTx.wait();

    // Approve the lending pool to spend the weth
    const approveTx = await weth.approve(
      lendingPool.address,
      ethers.utils.parseEther("1")
    );
    await approveTx.wait();

    // Sould fail if the first  deposit is lower than the minimum (1e10)
    await expect(lendingPool.deposit("10", owner.address)).to.be.revertedWith(
      "VL:VD:MIN_DEPOSIT"
    );

    // Deposit into the pool
    const depositTx2 = await lendingPool.deposit(
      ethers.utils.parseEther("1"),
      owner.address
    );
    await depositTx2.wait();

    // Sould fail to deposit the amount is 0
    await expect(
      lendingPool.deposit(ethers.utils.parseEther("0"), owner.address)
    ).to.be.revertedWith("VL:VD:AMOUNT_0");

    // Check the balance of the user in the pool
    const balance = await lendingPool.maxWithdraw(owner.address);
    expect(balance).to.equal(ethers.utils.parseEther("1"));

    // Should fail to deposit and exceed the safeguard
    await expect(
      lendingPool.deposit(await lendingMarket.getTVLSafeguard(), owner.address)
    ).to.be.revertedWith("VL:VD:SAFEGUARD_EXCEEDED");
  });
  it("Withdraws from the pool", async function () {
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
    const lendingPool = await ethers.getContractAt(
      "LendingPool",
      lendingPoolAddress
    );
    // Deposit into weth contract
    const depositTx = await weth.deposit({
      value: ethers.utils.parseEther("1"),
    });
    await depositTx.wait();
    // Approve the lending pool to spend the weth
    const approveTx = await weth.approve(
      lendingPool.address,
      ethers.utils.parseEther("1")
    );
    await approveTx.wait();
    // Deposit into the pool
    const depositTx2 = await lendingPool.deposit(
      ethers.utils.parseEther("1"),
      owner.address
    );
    await depositTx2.wait();

    // Should give an error when withdrawing 0
    await expect(
      lendingPool.withdraw(
        ethers.utils.parseEther("0"),
        owner.address,
        owner.address
      )
    ).to.be.revertedWith("VL:VW:AMOUNT_0");

    // withdraw from the pool
    const withdrawTx = await lendingPool.withdraw(
      ethers.utils.parseEther("1"),
      owner.address,
      owner.address
    );
    await withdrawTx.wait();
    // Check the balance of the user in the pool
    const balance = await lendingPool.maxWithdraw(owner.address);
    expect(balance).to.equal(ethers.utils.parseEther("0"));
  });
  it("Should be able add a new lending pool config", async function () {
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
    const lendingPool = await ethers.getContractAt(
      "LendingPool",
      lendingPoolAddress
    );

    // Define the new pool configuration
    const newPoolConfig = {
      maxLiquidatorDiscount: "300",
      auctioneerFeeRate: "50",
      liquidationFeeRate: "350",
      maxUtilizationRate: "8500",
    };

    // Call setPoolConfig function
    await lendingPool.connect(owner).setPoolConfig(newPoolConfig);

    // Call getPoolConfig function and check if the configuration is updated
    const updatedPoolConfig = await lendingPool.getPoolConfig();

    expect(updatedPoolConfig.maxLiquidatorDiscount).to.equal(
      newPoolConfig.maxLiquidatorDiscount
    );
    expect(updatedPoolConfig.auctioneerFee).to.equal(
      newPoolConfig.auctioneerFee
    );
    expect(updatedPoolConfig.liquidationFee).to.equal(
      newPoolConfig.liquidationFee
    );
    expect(updatedPoolConfig.maxUtilizationRate).to.equal(
      newPoolConfig.maxUtilizationRate
    );
  });
  it("Should get the correct pool debt", async function () {
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
    const lendingPool = await ethers.getContractAt(
      "LendingPool",
      lendingPoolAddress
    );

    // Deposit into weth contract
    const depositTx = await weth.deposit({
      value: ethers.utils.parseEther("1"),
    });
    await depositTx.wait();

    // Approve the lending pool to spend the weth
    const approveTx = await weth.approve(
      lendingPool.address,
      ethers.utils.parseEther("1")
    );
    await approveTx.wait();

    // Deposit into the pool
    const depositTx2 = await lendingPool.deposit(
      ethers.utils.parseEther("1"),
      owner.address
    );
    await depositTx2.wait();

    // Check the pool debt
    const poolDebt = await lendingPool.getDebt();
    expect(poolDebt).to.equal("0");

    // Mint an NFT & approve it to be used by the lending market
    const mintTx = await testNFT.mint(owner.address);
    await mintTx.wait();
    const approveNftTx = await testNFT.approve(lendingMarket.address, 0);
    await approveNftTx.wait();

    // Get the price signature for the NFT
    const priceSig = getPriceSig(
      testNFT.address,
      [0],
      "800000000000000", //Price of 0.08 ETH
      await time.latest(),
      nftOracle.address
    );

    // Borrow wETH using the NFT as collateral
    const borrowTx = await lendingMarket.borrow(
      owner.address,
      weth.address,
      "200000000000000", // 0.02 ETH
      testNFT.address,
      [0],
      0,
      priceSig.request,
      priceSig
    );
    await borrowTx.wait();

    // Check if the pool debt is updated
    const poolDebt2 = await lendingPool.getDebt();
    expect(poolDebt2).to.equal("200000000000000");
  });
  it("Should get the correct pool supply rate", async function () {
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
    const lendingPool = await ethers.getContractAt(
      "LendingPool",
      lendingPoolAddress
    );

    // Deposit into weth contract
    const depositTx = await weth.deposit({
      value: ethers.utils.parseEther("1"),
    });
    await depositTx.wait();

    // Approve the lending pool to spend the weth
    const approveTx = await weth.approve(
      lendingPool.address,
      ethers.utils.parseEther("1")
    );
    await approveTx.wait();

    // Deposit into the pool
    const depositTx2 = await lendingPool.deposit(
      ethers.utils.parseEther("1"),
      owner.address
    );
    await depositTx2.wait();

    // Check the pool supply rate
    expect(await lendingPool.getSupplyRate()).to.equal("0");

    // Mint an NFT & approve it to be used by the lending market
    const mintTx = await testNFT.mint(owner.address);
    await mintTx.wait();
    const approveNftTx = await testNFT.approve(lendingMarket.address, 0);
    await approveNftTx.wait();

    // Get the price signature for the NFT
    const priceSig = getPriceSig(
      testNFT.address,
      [0],
      ethers.utils.parseEther("1"),
      await time.latest(),
      nftOracle.address
    );

    // Borrow wETH using the NFT as collateral
    const borrowTx = await lendingMarket.borrow(
      owner.address,
      weth.address,
      ethers.utils.parseEther("0.29"),
      testNFT.address,
      [0],
      0,
      priceSig.request,
      priceSig
    );
    await borrowTx.wait();

    // Check if the pool supply rate is updated
    expect(await lendingPool.getSupplyRate()).to.equal("145");
  });
  it("Should get the correct pool utilization rate", async function () {
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
    const lendingPool = await ethers.getContractAt(
      "LendingPool",
      lendingPoolAddress
    );

    // Deposit into weth contract
    const depositTx = await weth.deposit({
      value: ethers.utils.parseEther("1"),
    });
    await depositTx.wait();

    // Approve the lending pool to spend the weth
    const approveTx = await weth.approve(
      lendingPool.address,
      ethers.utils.parseEther("1")
    );
    await approveTx.wait();

    // Deposit into the pool
    const depositTx2 = await lendingPool.deposit(
      ethers.utils.parseEther("1"),
      owner.address
    );
    await depositTx2.wait();

    // Check the pool supply rate
    expect(await lendingPool.getUtilizationRate()).to.equal("0");

    // Mint an NFT & approve it to be used by the lending market
    const mintTx = await testNFT.mint(owner.address);
    await mintTx.wait();
    const approveNftTx = await testNFT.approve(lendingMarket.address, 0);
    await approveNftTx.wait();

    // Get the price signature for the NFT
    const priceSig = getPriceSig(
      testNFT.address,
      [0],
      ethers.utils.parseEther("1"),
      await time.latest(),
      nftOracle.address
    );

    // Borrow wETH using the NFT as collateral
    const borrowTx = await lendingMarket.borrow(
      owner.address,
      weth.address,
      ethers.utils.parseEther("0.2"),
      testNFT.address,
      [0],
      0,
      priceSig.request,
      priceSig
    );
    await borrowTx.wait();

    // Check if the pool supply rate is updated
    expect(await lendingPool.getUtilizationRate()).to.equal(2000);
  });
  it("Should not be able to create a loan if the pool is paused", async function () {
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
    const lendingPool = await ethers.getContractAt(
      "LendingPool",
      lendingPoolAddress
    );

    // Deposit into weth contract
    const depositTx = await weth.deposit({
      value: ethers.utils.parseEther("1"),
    });
    await depositTx.wait();

    // Approve the lending pool to spend the weth
    const approveTx = await weth.approve(
      lendingPool.address,
      ethers.utils.parseEther("1")
    );
    await approveTx.wait();

    // Deposit into the pool
    const depositTx2 = await lendingPool.deposit(
      ethers.utils.parseEther("1"),
      owner.address
    );
    await depositTx2.wait();

    // Mint an NFT & approve it to be used by the lending market
    const mintTx = await testNFT.mint(owner.address);
    await mintTx.wait();
    const approveNftTx = await testNFT.approve(lendingMarket.address, 0);
    await approveNftTx.wait();

    // Get the price signature for the NFT
    const priceSig = getPriceSig(
      testNFT.address,
      [0],
      ethers.utils.parseEther("1"),
      await time.latest(),
      nftOracle.address
    );

    // Pause the pool
    const pauseTx = await lendingPool.setPause(true);
    await pauseTx.wait();

    // Expect the borrow to fail
    await expect(
      lendingMarket.borrow(
        owner.address,
        weth.address,
        ethers.utils.parseEther("0.2"),
        testNFT.address,
        [0],
        0,
        priceSig.request,
        priceSig
      )
    ).to.be.revertedWith("LP:POOL_PAUSED");

    // Unpause the pool
    const unpauseTx = await lendingPool.setPause(false);
    await unpauseTx.wait();

    // Borrow wETH using the NFT as collateral
    const borrowTx = await lendingMarket.borrow(
      owner.address,
      weth.address,
      ethers.utils.parseEther("0.2"),
      testNFT.address,
      [0],
      0,
      priceSig.request,
      priceSig
    );
    await borrowTx.wait();

    // Check if the user has a loan
    expect((await loanCenter.getLoan(0)).owner).to.equal(owner.address);
  });
});
