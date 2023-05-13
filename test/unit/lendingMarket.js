const { expect } = require("chai");
const { ethers } = require("hardhat");
const { BigNumber } = require("ethers");
const load = require("../helpers/_loadTest.js");
const { getPriceSig } = require("../helpers/getPriceSig.js");

describe("LendingMarket", function () {
  load.loadTestAlways(false);

  it("Should create a new lending pool", async function () {
    const tx = await lendingMarket.createLendingPool(
      testNFT.address,
      wethAddress
    );
    await tx.wait();

    // Get the lending pool address
    expect(
      await lendingMarket.getLendingPool(testNFT.address, wethAddress)
    ).to.not.equal(ethers.constants.AddressZero);
  });
  it("Should set lending pool manually", async function () {
    const tx = await lendingMarket.setLendingPool(
      testNFT.address,
      wethAddress,
      ethers.constants.AddressZero
    );
    await tx.wait();

    // Get the lending pool address
    expect(
      await lendingMarket.getLendingPool(testNFT.address, wethAddress)
    ).to.equal(ethers.constants.AddressZero);
  });
  it("Should set the TVL safeguard", async function () {
    const tx = await lendingMarket.setTVLSafeguard("1000000000000000000");
    await tx.wait();

    // Get the TVL safeguard
    expect(await lendingMarket.getTVLSafeguard()).to.equal(
      "1000000000000000000"
    );
  });

  it("Should set the default pool config", async function () {
    const tx = await lendingMarket.setDefaultPoolConfig({
      maxLiquidatorDiscount: "1000", // maxLiquidatorDiscount
      auctionerFee: "60", // defaultAuctionerFee
      liquidationFee: "300", // defaultProtocolLiquidationFee
      maxUtilizationRate: "8000", // defaultmaxUtilizationRate
    });
    await tx.wait();

    // Get the default pool config
    const defaultPoolConfig = await lendingMarket.getDefaultPoolConfig();
    expect(defaultPoolConfig.maxLiquidatorDiscount).to.equal("1000");
    expect(defaultPoolConfig.auctionerFee).to.equal("60");
    expect(defaultPoolConfig.liquidationFee).to.equal("300");
    expect(defaultPoolConfig.maxUtilizationRate).to.equal("8000");
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
    const approveNftTx = await testNFT.approve(lendingMarket.address, 0);
    await approveNftTx.wait();

    // Get the price signature for the NFT
    const priceSig = getPriceSig(
      testNFT.address,
      [0],
      "800000000000000", //Price of 0.08 ETH
      Math.floor(Date.now() / 1000),
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

    // Check if the borrower received the borrowed ETH
    expect(await weth.balanceOf(owner.address)).to.equal(
      BigNumber.from("200000000000000")
    );
    // Check if the loan center received the NFT
    expect(await testNFT.ownerOf(0)).to.equal(loanCenter.address);

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

  it("Should not be able to borrow an asset if the price has expired", async function () {
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
      Math.floor(Date.now() / 1000),
      nftOracle.address
    );

    // 10 minutes have passed, so the price has expired
    await ethers.provider.send("evm_increaseTime", [600]);

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
    ).to.be.revertedWith("T:V:DEADLINE_EXCEEDED");
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
      Math.floor(Date.now() / 1000),
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

    // Mint wETH to repay the loan
    const depositWethTx = await weth.deposit({ value: loanDebt });
    await depositWethTx.wait();

    // Aprove the lending pool to spend the wETH
    const approveTx = await weth.approve(
      await lendingMarket.getLendingPool(testNFT.address, weth.address),
      loanDebt
    );
    await approveTx.wait();

    const repayTx = await lendingMarket.repay(0, loanDebt);
    await repayTx.wait();

    // Check if the borrower received his NFT collateral back
    expect(await testNFT.ownerOf(0)).to.equal(owner.address);

    // Should revert if we try to repay again
    await expect(lendingMarket.repay(0, loanDebt)).to.be.revertedWith(
      "VL:VR:LOAN_NOT_FOUND"
    );
  });

  it("Should partially repay a loan", async function () {
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
      Math.floor(Date.now() / 1000),
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
    var loanDebt = await loanCenter.getLoanDebt(0);

    // Mint wETH to repay the loan
    const depositWethTx = await weth.deposit({ value: loanDebt });
    await depositWethTx.wait();

    // Aprove the lending pool to spend the wETH
    const approveTx = await weth.approve(
      await lendingMarket.getLendingPool(testNFT.address, weth.address),
      loanDebt.div(2)
    );
    await approveTx.wait();

    // Repay half of the loan
    const repayTx = await lendingMarket.repay(0, loanDebt.div(2));
    await repayTx.wait();

    // Check if the collateral is still with the pool
    expect(await testNFT.ownerOf(0)).to.equal(loanCenter.address);

    // Aprove the lending pool to spend the wETH
    const loanDebt2 = await loanCenter.getLoanDebt(0);
    const approveTx2 = await weth.approve(
      await lendingMarket.getLendingPool(testNFT.address, weth.address),
      loanDebt2
    );
    await approveTx2.wait();
    const repayTx2 = await lendingMarket.repay(0, loanDebt2);
    await repayTx2.wait();

    // Check if the borrower received his NFT collateral back
    expect(await testNFT.ownerOf(0)).to.equal(owner.address);
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

    // Mint and approve wETH to be used by the lending market
    const depositWethTx = await weth.deposit({ value: "1000000000000000000" });
    await depositWethTx.wait();
    const approveTx = await weth.approve(
      lendingMarket.address,
      "1000000000000000000"
    );
    await approveTx.wait();

    // Get the price signature for the NFT
    const priceSig = getPriceSig(
      testNFT.address,
      [0],
      "800000000000000", //Price of 0.08 ETH
      Math.floor(Date.now() / 1000),
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

    // Create a liquidation auction
    // Should revert if the loan cant be liquidated
    console.log("Creating liquidation auction");
    await expect(
      lendingMarket.createLiquidationAuction(
        0,
        "100000000000000", //Price of 0.01 ETH
        priceSig.request,
        priceSig
      )
    ).to.be.revertedWith("VL:VCLA:MAX_DEBT_NOT_EXCEEDED");

    // Get a new lower price signature for the NFT
    const priceSig2 = getPriceSig(
      testNFT.address,
      [0],
      "250000000000000", //Price of 0.025 ETH
      Math.floor(Date.now() / 1000),
      nftOracle.address
    );

    // Create a liquidation auction
    // Should revert if the price of the bid is too low
    console.log("Creating liquidation auction");
    await expect(
      lendingMarket.createLiquidationAuction(
        0,
        "50000000000000", //Price of 0.005 ETH
        priceSig2.request,
        priceSig2
      )
    ).to.be.revertedWith("VL:VCLA:BID_TOO_LOW");

    // Create a liquidation auction
    const auctionTx = await lendingMarket.createLiquidationAuction(
      0,
      "220000000000000", //Price of 0.022 ETH
      priceSig2.request,
      priceSig2
    );
    await auctionTx.wait();

    // Check if the auction was created
    const loanLiquidationData = await loanCenter.getLoanLiquidationData(0);
    expect(loanLiquidationData.auctioner).to.equal(owner.address);
    expect(loanLiquidationData.liquidator).to.equal(owner.address);
    expect(loanLiquidationData.auctionMaxBid).to.equal(
      BigNumber.from("220000000000000")
    );
    // Expect the auction starttime to have been in the last 5 minutes
    expect(loanLiquidationData.auctionStartTimestamp).to.be.gt(
      Math.floor(Date.now() / 1000) - 300
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

    // Mint and approve wETH to be used by the lending market
    const depositWethTx = await weth.deposit({ value: "1000000000000000000" });
    await depositWethTx.wait();
    const approveTx = await weth.approve(
      lendingMarket.address,
      "1000000000000000000"
    );
    await approveTx.wait();

    // Get the price signature for the NFT
    const priceSig = getPriceSig(
      testNFT.address,
      [0],
      "800000000000000", //Price of 0.08 ETH
      Math.floor(Date.now() / 1000),
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
      Math.floor(Date.now() / 1000),
      nftOracle.address
    );

    // Should revert if bidding on a liquidation auction that doesnt exist
    console.log("Bidding on liquidation auction");
    await expect(
      lendingMarket.bidLiquidationAuction(0, "220000000000000")
    ).to.be.revertedWith("VL:VBLA:AUCTION_NOT_FOUND");

    // Create a liquidation auction
    // Should revert if the price of the bid is too low
    const auctionTx = await lendingMarket.createLiquidationAuction(
      0,
      "220000000000000", //Price of 0.022 ETH
      priceSig2.request,
      priceSig2
    );
    await auctionTx.wait();

    // Should make a lower bid than the current bid
    console.log("Bidding on liquidation auction");
    await expect(
      lendingMarket.bidLiquidationAuction(0, "210000000000000")
    ).to.be.revertedWith("VL:VBLA:BID_TOO_LOW");

    // Should make a valid bid
    const bidTx = await lendingMarket.bidLiquidationAuction(
      0,
      "230000000000000"
    );
    await bidTx.wait();

    // Check if the auction was created
    const loanLiquidationData = await loanCenter.getLoanLiquidationData(0);
    expect(loanLiquidationData.auctioner).to.equal(owner.address);
    expect(loanLiquidationData.liquidator).to.equal(owner.address);
    expect(loanLiquidationData.auctionMaxBid).to.equal(
      BigNumber.from("230000000000000")
    );
    // Expect the auction starttime to have been in the last 5 minutes
    expect(loanLiquidationData.auctionStartTimestamp).to.be.gt(
      Math.floor(Date.now() / 1000) - 300
    );
  });

  it("Should claim the collateral of a liquidated loan", async function () {
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

    // Mint and approve wETH to be used by the lending market
    const depositWethTx = await weth.deposit({
      value: "1000000000000000000",
    });
    await depositWethTx.wait();
    const approveTx = await weth.approve(
      lendingMarket.address,
      "1000000000000000000"
    );
    await approveTx.wait();

    // Get the price signature for the NFT
    const priceSig = getPriceSig(
      testNFT.address,
      [0],
      "800000000000000", //Price of 0.08 ETH
      Math.floor(Date.now() / 1000),
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
      Math.floor(Date.now() / 1000),
      nftOracle.address
    );

    // Should revert if claiming on a liquidation auction that doesnt exist
    await expect(lendingMarket.claimLiquidation(0)).to.be.revertedWith(
      "VL:VCLA:AUCTION_NOT_FOUND"
    );

    // Create a liquidation auction
    const auctionTx = await lendingMarket.createLiquidationAuction(
      0,
      "220000000000000", //Price of 0.022 ETH
      priceSig2.request,
      priceSig2
    );
    await auctionTx.wait();

    // Should make a valid bid
    const bidTx = await lendingMarket.bidLiquidationAuction(
      0,
      "230000000000000"
    );
    await bidTx.wait();

    // Should revert if claiming on a liquidation auction that hasnt ended
    await expect(lendingMarket.claimLiquidation(0)).to.be.revertedWith(
      "VL:VCLA:AUCTION_NOT_FINISHED"
    );

    // Increase the time by 48 hours to end the auction
    await network.provider.send("evm_increaseTime", [172800]);

    // Claim the liquidation
    const claimTx = await lendingMarket.claimLiquidation(0);
    await claimTx.wait();

    // Check if the the collateral now belongs to the liquidator
    expect(await testNFT.ownerOf(0)).to.equal(owner.address);

    // Check if we can claim the collateral again
    await expect(lendingMarket.claimLiquidation(0)).to.be.revertedWith(
      "VL:VCLA:AUCTION_NOT_FOUND"
    );
  });
});
