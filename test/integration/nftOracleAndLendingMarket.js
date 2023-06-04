const { expect } = require("chai");
const { ethers } = require("hardhat");
const { BigNumber } = require("ethers");
const load = require("../helpers/_loadTest.js");
const { getPriceSig } = require("../helpers/getPriceSig.js");
const { time } = require("@nomicfoundation/hardhat-network-helpers");

describe("NFT Oracle And Lending Market", function () {
  load.loadTest(false);

  // Create a new trading pool and its associated trading gauge
  before(async () => {
    // Take a snapshot before the tests start
    snapshotId = await ethers.provider.send("evm_snapshot", []);
  });

  beforeEach(async function () {
    // Restore the blockchain state to the snapshot before each test
    await ethers.provider.send("evm_revert", [snapshotId]);

    // Take a snapshot before the tests start
    snapshotId = await ethers.provider.send("evm_snapshot", []);
  });

  it("NFT Oracle price change should be able liquidate loan", async function () {
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

    // Create a liquidation auction
    // Should revert if the loan cant be liquidated
    console.log("Creating liquidation auction");
    await expect(
      lendingMarket.createLiquidationAuction(
        owner.address,
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
      await time.latest(),
      nftOracle.address
    );

    // Create a liquidation auction
    // Should revert if the price of the bid is too low
    console.log("Creating liquidation auction");
    // Create a liquidation auction
    await expect(
      lendingMarket.createLiquidationAuction(
        owner.address,
        0,
        "220000000000000", //Price of 0.022 ETH
        priceSig2.request,
        priceSig2
      )
    ).to.not.be.reverted;
  });
});
