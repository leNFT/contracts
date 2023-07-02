const { ethers } = require("hardhat");
const { BigNumber } = require("ethers");
const { expect } = require("chai");
const load = require("../helpers/_loadTest.js");
const Chance = require("chance");
const { getPriceSig } = require("../helpers/getPriceSig.js");
const { time } = require("@nomicfoundation/hardhat-network-helpers");
const chance = new Chance();

const nTests = 100;

describe("Sell fuzzing", function () {
  load.loadTest(false);

  before(async function () {
    // Create a new trading pool
    const createPoolTx = await tradingPoolFactory.createTradingPool(
      testNFT.address,
      weth.address
    );
    createPoolTx.wait();

    tradingPool = await ethers.getContractAt(
      "TradingPool",
      await tradingPoolFactory.getTradingPool(testNFT.address, weth.address)
    );

    // Mint and approve 5 test NFTs
    for (let i = 0; i < 5; i++) {
      const mintTestNFTTx = await testNFT.mint(owner.address);
      await mintTestNFTTx.wait();
    }

    const approveNFTTx = await testNFT.setApprovalForAll(
      wethGateway.address,
      true
    );
    await approveNFTTx.wait();

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
      // Generate random values for the deposit arguments
      const numNfts = chance.integer({ min: 1, max: 5 });
      console.log("Num NFTs: " + numNfts);
      var sellNftIds = [];
      for (let j = 0; j < numNfts; j++) {
        sellNftIds.push(j);
      }
      const initialPrice = chance.integer({ min: 100, max: 10000 });
      // Exclude sell LPs (4) since this is a sell test and you cant sell against a sell LP
      const lpType = chance.integer({ min: 0, max: 3 });
      console.log("LP Type: " + lpType);

      // Generate a random fee and tokens ids for non buy LPs
      var fee = 0;
      if (lpType != 3) {
        fee = chance.integer({ min: 1, max: 8000 });
      }

      const curveAddress = chance.bool()
        ? linearCurve.address
        : exponentialCurve.address;

      var delta;
      if (curveAddress == linearCurve.address) {
        delta = chance.integer({ min: 0, max: 800 }); // between 0 and 800
        console.log("Linear Curve");
      } else {
        delta = chance.integer({ min: 0, max: 8000 }); // between 0 and 80%
        console.log("Exponential Curve");
      }

      const depositPromise = wethGateway.depositTradingPool(
        tradingPool.address,
        lpType,
        [],
        initialPrice,
        curveAddress,
        delta,
        fee,
        {
          value: initialPrice * sellNftIds.length,
        }
      );

      if (lpType != 3) {
        const userFeePercentage =
          (fee *
            (10000 - (await tradingPoolFactory.getProtocolFeePercentage()))) /
          10000;
        if (curveAddress == linearCurve.address) {
          if (
            delta < initialPrice &&
            (initialPrice - delta) * (10000 + userFeePercentage) >
              initialPrice * (10000 - userFeePercentage)
          ) {
            // should not revert
            await expect(depositPromise).to.not.be.reverted;
            sellTokens();
          } else {
            await expect(depositPromise).to.be.revertedWith(
              delta >= initialPrice
                ? "LPC:VLPP:INVALID_DELTA"
                : "LPC:VLPP:INVALID_FEE_DELTA_RATIO"
            );
          }
        } else {
          if (
            10000 * (10000 + userFeePercentage) >
            (10000 + delta) * (10000 - userFeePercentage)
          ) {
            // should not revert
            await expect(depositPromise).to.not.be.reverted;
            sellTokens();
          } else {
            await expect(depositPromise).to.be.revertedWith(
              "EPC:VLPP:INVALID_FEE_DELTA_RATIO"
            );
          }
        }
      } else {
        sellTokens();
      }
      async function sellTokens() {
        // Sell the tokens
        const sellTx = await wethGateway.sell(
          tradingPool.address,
          sellNftIds,
          new Array(numNfts).fill(0),
          0 // Will always be lower than the actual sell price
        );
        await sellTx.wait();

        // Check that the pool has all the NFTs
        const nftBalances = await testNFT.balanceOf(tradingPool.address);
        expect(nftBalances).to.equal(numNfts);
      }
    });
  }
});
