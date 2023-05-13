const { expect } = require("chai");
const { time } = require("@nomicfoundation/hardhat-network-helpers");
const { ethers } = require("hardhat");
const { BigNumber } = require("ethers");
const load = require("../helpers/_loadTest.js");
const { getPriceSig } = require("../helpers/getPriceSig.js");

describe("LoanCenter", function () {
  load.loadTestAlways(false);

  it("Should set the risk params for a collection", async function () {
    // Set the risk params
    const newMaxLTV = 4000;
    const newLiquidationThreshold = 2000;
    const setRiskParamsTx = await loanCenter.setCollectionRiskParameters(
      testNFT.address,
      newMaxLTV,
      newLiquidationThreshold
    );
    await setRiskParamsTx.wait();

    // Check the risk params
    expect(await loanCenter.getCollectionMaxLTV(testNFT.address)).to.equal(
      newMaxLTV
    );
    expect(
      await loanCenter.getCollectionLiquidationThreshold(testNFT.address)
    ).to.equal(newLiquidationThreshold);
  });
  it("Should get the correct amount of loans", async function () {
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
      ethers.utils.parseEther("0.08"), //Price of 0.08 ETH
      await time.latest(),
      nftOracle.address
    );

    // THe amount of loans should be 0
    expect(await loanCenter.getLoansCount()).to.equal(0);

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

    // The amount of loans should be 1
    expect(await loanCenter.getLoansCount()).to.equal(1);

    // Get loan debt
    const loanDebt = await loanCenter.getLoanDebt(0);

    const repayTx = await wethGateway.repay(0, {
      value: loanDebt,
    });
    await repayTx.wait();

    // The amount of loans should still be 1
    expect(await loanCenter.getLoansCount()).to.equal(1);
  });
  it("Should get the correct amount of user active loans", async function () {
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
      ethers.utils.parseEther("0.08"), //Price of 0.08 ETH
      await time.latest(),
      nftOracle.address
    );

    // THe amount of user active loans should be 0
    expect(await loanCenter.getUserActiveLoans(owner.address)).to.deep.equal(
      []
    );

    // Borrow wETH using the NFT as collateral
    const borrowTx = await lendingMarket.borrow(
      owner.address,
      weth.address,
      ethers.utils.parseEther("0.02"), // 0.02 ETH
      testNFT.address,
      [0],
      0,
      priceSig.request,
      priceSig
    );
    await borrowTx.wait();

    // The amount of user active loans should be 1
    expect(await loanCenter.getUserActiveLoans(owner.address)).to.deep.equal([
      BigNumber.from(0),
    ]);

    // Get loan debt
    const loanDebt = await loanCenter.getLoanDebt(0);

    const repayTx = await wethGateway.repay(0, {
      value: loanDebt,
    });
    await repayTx.wait();

    // The amount of loans should be 0
    expect(await loanCenter.getUserActiveLoans(owner.address)).to.deep.equal(
      []
    );
  });
  it("Should get the correct loan after borrowing", async function () {
    // Create a lending pool
    const tx = await lendingMarket.createLendingPool(
      testNFT.address,
      wethAddress
    );
    await tx.wait();
    // Deposit ETH into the lending pool
    const depositTx = await wethGateway.depositLendingPool(
      await lendingMarket.getLendingPool(testNFT.address, weth.address),
      { value: ethers.utils.parseEther("1") } // 1 ETH
    );
    await depositTx.wait();

    // Mint an NFT & approve it to be used by the lending market
    const mintTx = await testNFT.mint(owner.address);
    await mintTx.wait();
    const approveNftTx = await testNFT.approve(lendingMarket.address, 0);
    await approveNftTx.wait();

    // Get the lending pool
    const lendingPool = await lendingMarket.getLendingPool(
      testNFT.address,
      weth.address
    );

    // Get the lending pool contract
    const lendingPoolContract = await ethers.getContractAt(
      "LendingPool",
      lendingPool
    );

    // Get the current borrow rate from the lending pool
    const borrowRate = await lendingPoolContract.getBorrowRate();

    // Get the price signature for the NFT
    const priceSig = getPriceSig(
      testNFT.address,
      [0],
      ethers.utils.parseEther("0.08"), //Price of 0.08 ETH
      await time.latest(),
      nftOracle.address
    );

    // Borrow wETH using the NFT as collateral
    const borrowTx = await lendingMarket.borrow(
      owner.address,
      weth.address,
      ethers.utils.parseEther("0.02"), // 0.02 ETH
      testNFT.address,
      [0],
      0,
      priceSig.request,
      priceSig
    );
    await borrowTx.wait();

    // Get the EVM time
    const evmTime = await time.latest();

    // Get the loan
    const loan = await loanCenter.getLoan(0);

    // The loan should have the correct values
    expect(loan.owner).to.equal(owner.address);
    expect(await loanCenter.getLoanOwner(0)).to.equal(owner.address);
    expect(loan.state).to.equal(BigNumber.from(2));
    expect(await loanCenter.getLoanState(0)).to.equal(BigNumber.from(2));
    expect(loan.amount).to.equal(ethers.utils.parseEther("0.02"));
    expect(loan.borrowRate).to.equal(borrowRate);
    expect(loan.genesisNFTId).to.equal(0);
    expect(loan.pool).to.equal(lendingPool);
    expect(await loanCenter.getLoanTokenIds(0)).to.deep.equal([
      BigNumber.from(0),
    ]);
    expect(loan.nftTokenIds).to.deep.equal([BigNumber.from(0)]);
    expect(loan.nftAsset).to.equal(testNFT.address);
    expect(await loanCenter.getLoanCollectionAddress(0)).to.equal(
      testNFT.address
    );
    expect(await loanCenter.getNFTLoanId(testNFT.address, 0)).to.equal(
      BigNumber.from(0)
    );

    // Init timestamp must be the same as the debt timestamp at this point
    expect(loan.initTimestamp).to.equal(loan.debtTimestamp);

    // init timestamp must be less than 30 seconds ago
    expect(loan.initTimestamp).to.be.equal(evmTime);
  });
  it("Should get the correct loan liquidation data", async function () {
    // Create a lending pool
    const tx = await lendingMarket.createLendingPool(
      testNFT.address,
      wethAddress
    );
    await tx.wait();
    // Deposit ETH into the lending pool
    const depositTx = await wethGateway.depositLendingPool(
      await lendingMarket.getLendingPool(testNFT.address, weth.address),
      { value: ethers.utils.parseEther("1") } // 1 ETH
    );
    await depositTx.wait();

    // Mint an NFT & approve it to be used by the lending market
    const mintTx = await testNFT.mint(owner.address);
    await mintTx.wait();
    const approveNftTx = await testNFT.approve(lendingMarket.address, 0);
    await approveNftTx.wait();

    // SHould throw an error since the loan doesn't exist yet
    await expect(loanCenter.getLoanLiquidationData(0)).to.be.revertedWith(
      "LC:UNEXISTENT_LOAN"
    );

    // Get the price signature for the NFT
    const priceSig = getPriceSig(
      testNFT.address,
      [0],
      ethers.utils.parseEther("0.08"), //Price of 0.08 ETH
      await time.latest(),
      nftOracle.address
    );

    // Borrow wETH using the NFT as collateral
    const borrowTx = await lendingMarket.borrow(
      owner.address,
      weth.address,
      ethers.utils.parseEther("0.02"), // 0.02 ETH
      testNFT.address,
      [0],
      0,
      priceSig.request,
      priceSig
    );
    await borrowTx.wait();

    // Get the loan liquidation data
    const loanLiquidationData = await loanCenter.getLoanLiquidationData(0);

    // The loan liquidation data should have the correct values (none since the loan is in auction)
    expect(loanLiquidationData.auctioner).to.equal(
      ethers.constants.AddressZero
    );
    expect(loanLiquidationData.liquidator).to.equal(
      ethers.constants.AddressZero
    );
    expect(loanLiquidationData.auctionStartTimestamp).to.equal(0);
    expect(loanLiquidationData.auctionMaxBid).to.equal(0);

    // Get a new price signature for the NFT that allows liquidation
    const priceSig2 = getPriceSig(
      testNFT.address,
      [0],
      ethers.utils.parseEther("0.03"), //Price of 0.01 ETH
      await time.latest(),
      nftOracle.address
    );

    // MInt and approve the NFT to be used by the lending market
    const depositWethTx = await weth.deposit({
      value: ethers.utils.parseEther("0.025"),
    });
    await depositWethTx.wait();
    const approveTx = await weth.approve(
      lendingMarket.address,
      ethers.utils.parseEther("0.025")
    );
    await approveTx.wait();

    // Liquidate the loan
    const liquidateTx = await lendingMarket.createLiquidationAuction(
      0,
      ethers.utils.parseEther("0.025"),
      priceSig2.request,
      priceSig2
    );
    await liquidateTx.wait();

    // Get the EVM time
    const evmTime = await time.latest();

    // Check if the loan state is 'auctioned'
    expect(await loanCenter.getLoanState(0)).to.equal(BigNumber.from(4));

    // Get the loan liquidation data
    const loanLiquidationData2 = await loanCenter.getLoanLiquidationData(0);
    expect(loanLiquidationData2.auctioner).to.equal(owner.address);
    expect(loanLiquidationData2.liquidator).to.equal(owner.address);
    expect(loanLiquidationData2.auctionStartTimestamp).to.be.equal(evmTime);
    expect(loanLiquidationData2.auctionMaxBid).to.equal(
      ethers.utils.parseEther("0.025")
    );
  });
  it("Should get the correct max debt for a loan", async function () {
    //Create a lending pool
    const tx = await lendingMarket.createLendingPool(
      testNFT.address,
      wethAddress
    );
    await tx.wait();
    // Deposit ETH into the lending pool
    const depositTx = await wethGateway.depositLendingPool(
      await lendingMarket.getLendingPool(testNFT.address, weth.address),
      { value: ethers.utils.parseEther("1") } // 1 ETH
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
      ethers.utils.parseEther("0.08"), //Price of 0.08 ETH
      await time.latest(),
      nftOracle.address
    );
    // Borrow wETH using the NFT as collateral
    const borrowTx = await lendingMarket.borrow(
      owner.address,
      weth.address,
      ethers.utils.parseEther("0.02"), // 0.02 ETH
      testNFT.address,
      [0],
      0,
      priceSig.request,
      priceSig
    );
    await borrowTx.wait();

    // Get the max debt for the loan
    const maxLTV = await loanCenter.getCollectionLiquidationThreshold(
      testNFT.address
    );
    const maxDebt = BigNumber.from(ethers.utils.parseEther("0.08"))
      .mul(maxLTV)
      .div(10000);
    expect(maxDebt).to.equal(maxDebt);
  });
  it("Should get the correct debt for a loan", async function () {
    //Create a lending pool
    const tx = await lendingMarket.createLendingPool(
      testNFT.address,
      wethAddress
    );
    await tx.wait();
    // Get the lending pool
    const lendingPool = await lendingMarket.getLendingPool(
      testNFT.address,
      weth.address
    );
    // Deposit ETH into the lending pool
    const depositTx = await wethGateway.depositLendingPool(
      lendingPool,
      { value: ethers.utils.parseEther("1") } // 1 ETH
    );
    await depositTx.wait();
    // Mint an NFT & approve it to be used by the lending market
    const mintTx = await testNFT.mint(owner.address);
    await mintTx.wait();
    const approveNftTx = await testNFT.approve(lendingMarket.address, 0);
    await approveNftTx.wait();

    // Get the lending pool contract
    const lendingPoolContract = await ethers.getContractAt(
      "LendingPool",
      lendingPool
    );

    // Get the current borrow rate for a loan
    const borrowRate = await lendingPoolContract.getBorrowRate();

    // Get the price signature for the NFT
    const priceSig = getPriceSig(
      testNFT.address,
      [0],
      ethers.utils.parseEther("0.08"), //Price of 0.08 ETH
      await time.latest(),
      nftOracle.address
    );
    // Borrow wETH using the NFT as collateral
    const borrowTx = await lendingMarket.borrow(
      owner.address,
      weth.address,
      ethers.utils.parseEther("0.02"), // 0.02 ETH
      testNFT.address,
      [0],
      0,
      priceSig.request,
      priceSig
    );
    await borrowTx.wait();

    // Set the next block timestamp to be 1 hour after the loan was created
    await time.increase(60 * 60);

    // Get the incremental timestamp
    const incrementalTimestamp =
      Math.floor((await time.latest()) / (30 * 60) + 1) * 30 * 60;

    // Get the loan debt after 1 hour
    const loanDebtTimestamp = (await loanCenter.getLoan(0)).debtTimestamp;

    const loanInterest = BigNumber.from(ethers.utils.parseEther("0.02"))
      .mul(incrementalTimestamp - loanDebtTimestamp)
      .mul(borrowRate)
      .div(10000)
      .div(365 * 86400);

    const loanDebt = BigNumber.from(ethers.utils.parseEther("0.02")).add(
      loanInterest
    );

    expect(await loanCenter.getLoanDebt(0)).to.equal(loanDebt);
  });
});
