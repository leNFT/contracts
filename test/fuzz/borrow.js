const { ethers } = require("hardhat");
const { BigNumber } = require("ethers");
const { expect } = require("chai");
const load = require("../helpers/_loadTest.js");
const Chance = require("chance");
const { getPriceSig } = require("../helpers/getPriceSig.js");
const { time } = require("@nomicfoundation/hardhat-network-helpers");
const chance = new Chance();

const nTests = 100;

describe("Borrow fuzzing", function () {
  load.loadTest(false);

  before(async function () {
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

    // Get the max LTV from the loan center
    maxLTV = await loanCenter.getCollectionMaxLTV(testNFT.address);
    console.log("Max LTV: " + maxLTV);

    // Take a snapshot before the tests start
    snapshotId = await ethers.provider.send("evm_snapshot", []);
  });

  beforeEach(async function () {
    // Restore the blockchain state to the snapshot before each test
    await ethers.provider.send("evm_revert", [snapshotId]);

    // Take a snapshot before the tests start
    snapshotId = await ethers.provider.send("evm_snapshot", []);
  });

  for (let i = 0; i < nTests; i++) {
    it(`Fuzz test iteration ${i}`, async function () {
      // Generate random price from 100 to 1000 wei
      const price = chance.integer({ min: 100, max: 1000 });
      console.log("Price: " + price);

      // Generate random borrow amount from 100 to 300 wei
      const borrowAmount = chance.integer({ min: 100, max: 300 });
      console.log("Borrow amount: " + borrowAmount);

      // Get the price signature for the NFT
      const priceSig = getPriceSig(
        testNFT.address,
        [0],
        price.toString(), // use the random price
        Math.floor(Date.now() / 1000),
        nftOracle.address
      );

      // Borrow wETH using the NFT as collateral
      const borrowPromise = lendingMarket.borrow(
        owner.address,
        weth.address,
        borrowAmount.toString(), // use the random borrow amount
        testNFT.address,
        [0],
        0,
        priceSig.request,
        priceSig
      );

      const maxAmount = Math.round((price * maxLTV.toNumber()) / 10000);

      if (borrowAmount <= maxAmount) {
        // should not revert if borrowAmount/price <= maxLTV
        await expect(borrowPromise).to.not.be.reverted;
      } else {
        // should revert if borrowAmount/price > maxLTV
        await expect(borrowPromise).to.be.revertedWith(
          "VL:VB:MAX_LTV_EXCEEDED"
        );
      }
    });
  }
});
