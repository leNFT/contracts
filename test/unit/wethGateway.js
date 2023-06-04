const { expect } = require("chai");
const { ethers } = require("hardhat");
const { BigNumber } = require("ethers");
const load = require("../helpers/_loadTest.js");
const { getPriceSig } = require("../helpers/getPriceSig.js");
const { time } = require("@nomicfoundation/hardhat-network-helpers");

describe("WETHGateway", () => {
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

  it("Deposit Lending Pool", async function () {
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
    const depositTx = await wethGateway.depositLendingPool(lendingPoolAddress, {
      value: ethers.utils.parseEther("1"),
    });
    await depositTx.wait();

    // Check the balance of the user in the pool
    const balance = await lendingPool.maxWithdraw(owner.address);
    expect(balance).to.equal(ethers.utils.parseEther("1"));
  });
  it("Withdraw from lending pool", async function () {
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
    // Deposit into pool
    const depositTx = await wethGateway.depositLendingPool(lendingPoolAddress, {
      value: ethers.utils.parseEther("1"),
    });
    await depositTx.wait();

    // Approve the wethGateway to withdraw from the pool
    const approveTx = await lendingPool.approve(
      wethGateway.address,
      ethers.utils.parseEther("1")
    );
    await approveTx.wait();

    // Check the ETH balance of the user in the pool before withdraw
    const balanceBefore = await ethers.provider.getBalance(owner.address);

    // withdraw from the pool
    const withdrawTx = await wethGateway.withdrawLendingPool(
      lendingPoolAddress,
      ethers.utils.parseEther("1")
    );
    const withdrawTxReceipt = await withdrawTx.wait();

    // Calculate gas fees
    const gasUsed = withdrawTxReceipt.gasUsed;
    const gasPrice = withdrawTx.gasPrice;
    const gasFees = gasUsed.mul(gasPrice);

    // Check the balance of the user in the pool after withdraw
    const balanceAfter = await ethers.provider.getBalance(owner.address);

    // Check the difference between the balance before and after
    expect(balanceAfter.sub(balanceBefore).add(gasFees)).to.equal(
      ethers.utils.parseEther("1")
    );
    // Check the balance of the user in the pool
    const balance = await lendingPool.maxWithdraw(owner.address);
    expect(balance).to.equal(ethers.utils.parseEther("0"));
  });
  it("Should borrow an asset from a lending pool using an NFT as collateral", async function () {
    // Create a lending pool
    const tx = await lendingMarket.createLendingPool(
      testNFT.address,
      wethAddress
    );
    await tx.wait();
    // Deposit ETH into the lending pool
    const depositTx = await wethGateway.depositLendingPool(
      await lendingMarket.getLendingPool(testNFT.address, weth.address),
      { value: "1000000000000000000" } // 1 ETH
    );
    await depositTx.wait();

    // Mint an NFT & approve it to be used by the lending market
    const mintTx = await testNFT.mint(owner.address);
    await mintTx.wait();
    const approveNftTx = await testNFT.approve(wethGateway.address, 0);
    await approveNftTx.wait();

    // Get the price signature for the NFT
    const priceSig = getPriceSig(
      testNFT.address,
      [0],
      "800000000000000", //Price of 0.08 ETH
      await time.latest(),
      nftOracle.address
    );

    // Get the balance of the user before borrowing
    const balanceBefore = await ethers.provider.getBalance(owner.address);

    // Borrow ETH using the NFT as collateral
    const borrowTx = await wethGateway.borrow(
      "200000000000000", // 0.02 ETH
      testNFT.address,
      [0],
      0,
      priceSig.request,
      priceSig
    );

    // Get the receipt of the transaction to calculate gas fees
    const borrowTxReceipt = await borrowTx.wait();
    const gasUsed = borrowTxReceipt.gasUsed;
    const gasPrice = borrowTx.gasPrice;
    const gasFees = gasUsed.mul(gasPrice);

    // Get the balance of the user after borrowing
    const balanceAfter = await ethers.provider.getBalance(owner.address);

    // Check if the borrower received the borrowed ETH
    expect(balanceAfter.sub(balanceBefore).add(gasFees)).to.equal(
      "200000000000000"
    );
    // Check if the loan center received the NFT
    expect(await testNFT.ownerOf(0)).to.equal(lendingMarket.address);

    // Get the loan from the loan center and check if it's valid
    const loan = await loanCenter.getLoan(0);
    expect(loan.owner).to.equal(owner.address);
    expect(loan.nftAsset).to.equal(testNFT.address);
    expect(loan.nftTokenIds[0]).to.equal(BigNumber.from(0));
    expect(loan.amount).to.equal(BigNumber.from("200000000000000"));
    expect(loan.genesisNFTId).to.equal(0);
    expect(loan.state).to.equal(2);
    expect(loan.pool).to.equal(
      await lendingMarket.getLendingPool(testNFT.address, weth.address)
    );

    // Should revert if we try to borrow again with the same NFT
    await expect(
      lendingMarket.borrow(
        owner.address,
        weth.address,
        "200000000000000", // 0.02 ETH
        testNFT.address,
        [0],
        0,
        priceSig.request,
        priceSig
      )
    ).to.be.revertedWith("ERC721: transfer from incorrect owner");
  });
  it("Should be able repay an active loan", async function () {
    // Create a lending pool
    const tx = await lendingMarket.createLendingPool(
      testNFT.address,
      wethAddress
    );
    await tx.wait();
    // Deposit ETH into the lending pool
    const depositTx = await wethGateway.depositLendingPool(
      await lendingMarket.getLendingPool(testNFT.address, weth.address),
      { value: "1000000000000000000" } // 1 ETH
    );
    await depositTx.wait();

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

    // Get loan debt
    const loanDebt = await loanCenter.getLoanDebt(0);

    const repayTx = await wethGateway.repay(0, {
      value: loanDebt,
    });
    await repayTx.wait();

    // Check if the borrower received his NFT collateral back
    expect(await testNFT.ownerOf(0)).to.equal(owner.address);
  });
  it("Should be able repay an auctioned loan", async function () {
    // Create a lending pool
    const tx = await lendingMarket.createLendingPool(
      testNFT.address,
      wethAddress
    );
    await tx.wait();
    // Deposit ETH into the lending pool
    const depositTx = await wethGateway.depositLendingPool(
      await lendingMarket.getLendingPool(testNFT.address, weth.address),
      { value: "1000000000000000000" } // 1 ETH
    );
    await depositTx.wait();

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

    const priceSig2 = getPriceSig(
      testNFT.address,
      [0],
      "250000000000000", // Price of 0.025 ETH
      await time.latest(),
      nftOracle.address
    );

    const depositWethTx = await weth.deposit({
      value: "220000000000000",
    });
    await depositWethTx.wait();
    const approveTx = await weth.approve(
      lendingMarket.address,
      "220000000000000"
    );
    await approveTx.wait();

    // Create a liquidation auction
    const auctionTx = await lendingMarket.createLiquidationAuction(
      owner.address,
      0,
      "220000000000000", // Bid of 0.022 ETH
      priceSig2.request,
      priceSig2
    );
    await auctionTx.wait();

    //Get the acutioneer fee
    const auctioneerFee = await loanCenter.getLoanAuctioneerFee(0);

    // Get loan debt
    const loanDebt = await loanCenter.getLoanDebt(0);

    const repayTx = await wethGateway.repay(0, {
      value: BigNumber.from(loanDebt).add(auctioneerFee),
    });
    await repayTx.wait();

    // Check if the borrower received his NFT collateral back
    expect(await testNFT.ownerOf(0)).to.equal(owner.address);
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
      wethGateway.address,
      true
    );
    await approveNFTTx.wait();

    const depositTx = await wethGateway.depositTradingPool(
      tradingPool.address,
      0,
      [0],
      "100000000000000",
      exponentialCurve.address,
      "50",
      "500",
      {
        value: "100000000000000",
      }
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

    // Approve the weth gateway to spend the lp tokens
    const approveLPTx = await tradingPool.setApprovalForAll(
      wethGateway.address,
      true
    );
    await approveLPTx.wait();

    // Get the balance of the user before removing liquidity
    const balanceBefore = await ethers.provider.getBalance(owner.address);

    // Remove the liquidity
    const removeLiquidityTx = await wethGateway.withdrawTradingPool(
      tradingPool.address,
      0
    );

    // Get transaction details
    const removeTxDetails = await ethers.provider.getTransaction(
      removeLiquidityTx.hash
    );
    console.log(removeTxDetails);
    const removeTxReceipt = await removeLiquidityTx.wait();
    console.log(removeTxReceipt);

    // Calculate gas fees
    const gasUsed = removeTxReceipt.gasUsed;
    const gasPrice = removeTxDetails.gasPrice;
    const gasFees = gasUsed.mul(gasPrice);

    // Get the balance of the user after removing liquidity
    const balanceAfter = await ethers.provider.getBalance(owner.address);

    // The balance after should incude the withdrawn amount - the gas cost
    expect(balanceAfter).to.equal(
      balanceBefore.add("100000000000000").sub(gasFees)
    );

    // The NFT should be returned to the user
    expect(await testNFT.ownerOf(0)).to.equal(owner.address);

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

    // Approve the weth gateway to spend the lp tokens
    const approveLPTx = await tradingPool.setApprovalForAll(
      wethGateway.address,
      true
    );
    await approveLPTx.wait();

    // Get the balance of the user before removing liquidity
    const balanceBefore = await ethers.provider.getBalance(owner.address);

    // Remove the liquidity
    const removeLiquidityBatchTx = await wethGateway.withdrawBatchTradingPool(
      tradingPool.address,
      [0, 1]
    );

    // Get transaction details
    const removeBatchTxDetails = await ethers.provider.getTransaction(
      removeLiquidityBatchTx.hash
    );
    const removeBatchTxReceipt = await removeBatchTxDetails.wait();

    // Calculate gas fees
    const gasUsed = removeBatchTxReceipt.gasUsed;
    const gasPrice = removeBatchTxDetails.gasPrice;
    const gasFees = gasUsed.mul(gasPrice);

    // Get the balance of the user after removing liquidity
    const balanceAfter = await ethers.provider.getBalance(owner.address);

    // The balance after should incude the withdrawn amount - the gas cost
    expect(balanceAfter).to.equal(
      balanceBefore.add("200000000000000").sub(gasFees)
    );

    // The NFTs should be returned to the user
    expect(await testNFT.ownerOf(0)).to.equal(owner.address);
    expect(await testNFT.ownerOf(1)).to.equal(owner.address);

    // The lp count should be still be 2
    expect(await tradingPool.getLpCount()).to.equal(2);

    // Should throw an error when trying to get the lps
    await expect(tradingPool.getLP(0)).to.be.revertedWith("TP:LP_NOT_FOUND");
    await expect(tradingPool.getLP(1)).to.be.revertedWith("TP:LP_NOT_FOUND");
  });
  it("Should be able to buy from a trading pool", async function () {
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

    // Balance before
    const balanceBefore = await ethers.provider.getBalance(owner.address);

    // Buy the tokens
    const buyTx = await wethGateway.buy(
      tradingPool.address,
      [0],
      "105000000000000",
      {
        value: "105000000000000",
      }
    );

    // Get transaction details
    const buyTxDetails = await ethers.provider.getTransaction(buyTx.hash);
    const buyTxReceipt = await buyTxDetails.wait();

    // Calculate gas fees
    const gasUsed = buyTxReceipt.gasUsed;
    const gasPrice = buyTxDetails.gasPrice;
    const gasFees = gasUsed.mul(gasPrice);

    // Balance after
    const balanceAfter = await ethers.provider.getBalance(owner.address);

    // The balance after should be the balance before - the gas cost
    expect(balanceAfter).to.equal(
      balanceBefore.sub(gasFees).sub("105000000000000")
    );

    // Should now own both tokens
    expect(await testNFT.ownerOf(0)).to.equal(owner.address);

    // Get the lp
    const lp = await tradingPool.getLP(0);
    expect(lp.nftIds).to.deep.equal([]);
    expect(lp.tokenAmount).to.equal("204500000000000");
    expect(lp.spotPrice).to.equal("100500000000000");
  });
  it("Should be able to sell to a liquidity pool", async function () {
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
      wethGateway.address,
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

    // Balance before
    const balanceBefore = await ethers.provider.getBalance(owner.address);

    // Sell the tokens
    const sellTx = await wethGateway.sell(
      tradingPool.address,
      [0],
      [0],
      "47500000000000"
    );

    // Get transaction details
    const sellTxDetails = await ethers.provider.getTransaction(sellTx.hash);
    const sellTxReceipt = await sellTxDetails.wait();

    // Calculate gas fees
    const gasUsed = sellTxReceipt.gasUsed;
    const gasPrice = sellTxDetails.gasPrice;
    const gasFees = gasUsed.mul(gasPrice);

    // Balance after
    const balanceAfter = await ethers.provider.getBalance(owner.address);

    // The balance after should be the balance before - the gas cost
    expect(balanceAfter).to.equal(
      balanceBefore.sub(gasFees).add("47500000000000")
    );

    // Should now own the token
    expect(await testNFT.ownerOf(0)).to.equal(tradingPool.address);

    // Get the lp
    const lp = await tradingPool.getLP(0);
    expect(lp.nftIds).to.deep.equal([BigNumber.from(0)]);
    expect(lp.tokenAmount).to.equal("52250000000000");
    expect(lp.spotPrice).to.equal("49751243781095");
  });
  it("Should swap between two assets ", async function () {
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

    // Balance before
    const balanceBefore = await ethers.provider.getBalance(owner.address);

    const swapTx = await wethGateway.swap(
      buyPoolAddress,
      sellPoolAddress,
      [0],
      "105000000000000", // effective price will be 105000000000000
      [1],
      [0],
      "95000000000000", // effective price will be 95000000000000
      {
        value: BigNumber.from("105000000000000").sub("95000000000000"),
      }
    );

    // Get transaction details
    const swapTxDetails = await ethers.provider.getTransaction(swapTx.hash);
    const swapTxReceipt = await swapTxDetails.wait();

    // Calculate gas fees
    const gasUsed = swapTxReceipt.gasUsed;
    const gasPrice = swapTxDetails.gasPrice;
    const gasFees = gasUsed.mul(gasPrice);

    // Calculate net balance change from the swap
    const balanceChange =
      BigNumber.from("105000000000000").sub("95000000000000");

    // Check the balance
    expect(await ethers.provider.getBalance(owner.address)).to.equal(
      balanceBefore.sub(balanceChange).sub(gasFees)
    );

    expect(await testNFT2.ownerOf(0)).to.equal(owner.address);
    expect(await testNFT.ownerOf(0)).to.equal(sellPoolAddress);
  });
  it("Should deposit a bribe", async function () {
    // Create a trading pool and then a trading gauge
    const createTx = await tradingPoolFactory.createTradingPool(
      testNFT.address,
      wethAddress
    );
    await createTx.wait();
    const tradingPoolAddress = await tradingPoolFactory.getTradingPool(
      testNFT.address,
      wethAddress
    );
    tradingPool = await ethers.getContractAt("TradingPool", tradingPoolAddress);
    // Create a new trading gauge and add it to the gauge controller
    const TradingGauge = await ethers.getContractFactory("TradingGauge");
    tradingGauge = await TradingGauge.deploy(
      addressProvider.address,
      tradingPool.address
    );
    await tradingGauge.deployed();

    // Add both the trading gauge to the gauge controller
    const addGaugeTx = await gaugeController.addGauge(tradingGauge.address);
    await addGaugeTx.wait();

    const epoch = (await votingEscrow.getEpoch(await time.latest())).toNumber();

    // Owner should have 0 balance in bribes
    expect(
      await bribes.getUserBribes(
        weth.address,
        tradingGauge.address,
        epoch + 1,
        owner.address
      )
    ).to.equal(0);

    // Should deposit the bribe
    const depositBribeTx = await wethGateway.depositBribe(
      tradingGauge.address,
      {
        value: ethers.utils.parseEther("1"),
      }
    );
    await depositBribeTx.wait();

    // Owner should have an 1 ETH bribe
    expect(
      await bribes.getUserBribes(
        weth.address,
        tradingGauge.address,
        epoch + 1,
        owner.address
      )
    ).to.equal(ethers.utils.parseEther("1"));
  });
  it("Should create a liquidation auction", async function () {
    // Create a lending pool
    const tx = await lendingMarket.createLendingPool(
      testNFT.address,
      wethAddress
    );
    await tx.wait();
    // Deposit ETH into the lending pool
    const depositTx = await wethGateway.depositLendingPool(
      await lendingMarket.getLendingPool(testNFT.address, weth.address),
      { value: "1000000000000000000" } // 1 ETH
    );
    await depositTx.wait();

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

    // Get a new lower price signature for the NFT
    const priceSig2 = getPriceSig(
      testNFT.address,
      [0],
      "250000000000000", //Price of 0.025 ETH
      await time.latest(),
      nftOracle.address
    );

    // Create a liquidation auction
    const auctionTx = await wethGateway.createLiquidationAuction(
      0,
      priceSig2.request,
      priceSig2,
      {
        value: "220000000000000", // 0.22 ETH
      }
    );
    await auctionTx.wait();

    // Get the created auction timestamp
    const creationTimetamp = await time.latest();

    // Check if the auction was created
    const loanLiquidationData = await loanCenter.getLoanLiquidationData(0);
    expect(loanLiquidationData.auctioneer).to.equal(owner.address);
    expect(loanLiquidationData.liquidator).to.equal(owner.address);
    expect(loanLiquidationData.auctionMaxBid).to.equal(
      BigNumber.from("220000000000000")
    );
    // Expect the auction starttime to have been in the last 5 minutes
    expect(loanLiquidationData.auctionStartTimestamp).to.equal(
      creationTimetamp
    );
  });
  it("Should bid on a liquidation auction", async function () {
    // Create a lending pool
    const tx = await lendingMarket.createLendingPool(
      testNFT.address,
      wethAddress
    );
    await tx.wait();
    // Deposit ETH into the lending pool
    const depositTx = await wethGateway.depositLendingPool(
      await lendingMarket.getLendingPool(testNFT.address, weth.address),
      { value: "1000000000000000000" } // 1 ETH
    );
    await depositTx.wait();

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

    // Get a new lower price signature for the NFT
    const priceSig2 = getPriceSig(
      testNFT.address,
      [0],
      "250000000000000", //Price of 0.025 ETH
      await time.latest(),
      nftOracle.address
    );

    // Create a liquidation auction
    const auctionTx = await wethGateway.createLiquidationAuction(
      0,
      priceSig2.request,
      priceSig2,
      {
        value: "220000000000000", // 0.22 ETH
      }
    );
    await auctionTx.wait();

    // Get the created auction timestamp
    const creationTimetamp = await time.latest();

    // Should make a valid bid
    const bidTx = await wethGateway.bidLiquidationAuction(0, {
      value: "230000000000000", // 0.23 ETH
    });
    await bidTx.wait();

    // Check if the auction was created
    const loanLiquidationData = await loanCenter.getLoanLiquidationData(0);
    expect(loanLiquidationData.auctioneer).to.equal(owner.address);
    expect(loanLiquidationData.liquidator).to.equal(owner.address);
    expect(loanLiquidationData.auctionMaxBid).to.equal(
      BigNumber.from("230000000000000")
    );
    expect(loanLiquidationData.auctionStartTimestamp).to.equal(
      creationTimetamp
    );
  });
});
