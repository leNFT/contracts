const { ethers } = require("hardhat");
const { BigNumber } = require("ethers");
const { expect } = require("chai");
const load = require("../helpers/_loadTest.js");
const Chance = require("chance");
const { getPriceSig } = require("../helpers/getPriceSig.js");
const { time } = require("@nomicfoundation/hardhat-network-helpers");
const chance = new Chance();

const nTests = 100;
var counter = 0;

describe("Buy fuzzing", function () {
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
      var poolNftIds = [];
      for (let j = 0; j < numNfts; j++) {
        poolNftIds.push(j);
      }
      const initialPrice = chance.integer({ min: 100, max: 10000 });
      // Exclude buy LPs (3) since this is a buy test and you cant buy against a buy LP
      let lpType;
      do {
        lpType = chance.integer({ min: 0, max: 4 });
      } while (lpType === 3);
      console.log("LP Type: " + lpType);

      // Generate a random fee and tokens ids for non buy LPs
      var fee = 0;
      if (lpType != 4) {
        fee = chance.integer({ min: 0, max: 8000 });
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
        poolNftIds,
        initialPrice,
        curveAddress,
        delta,
        fee,
        {
          value: 0,
        }
      );

      if (lpType != 4) {
        if (curveAddress == linearCurve.address) {
          if (
            delta < initialPrice &&
            (initialPrice - delta) * (10000 + fee) >
              initialPrice * (10000 - fee)
          ) {
            // should not revert
            await expect(depositPromise).to.not.be.reverted;
            buyTokens();
          } else {
            await expect(depositPromise).to.be.revertedWith(
              delta >= initialPrice
                ? "LPC:VLPP:INVALID_DELTA"
                : "LPC:VLPP:INVALID_FEE_DELTA_RATIO"
            );
          }
        } else {
          if (10000 * (10000 + fee) > (10000 + delta) * (10000 - fee)) {
            // should not revert
            await expect(depositPromise).to.not.be.reverted;
            buyTokens();
          } else {
            await expect(depositPromise).to.be.revertedWith(
              "EPC:VLPP:INVALID_FEE_DELTA_RATIO"
            );
          }
        }
      } else {
        buyTokens();
      }
      async function buyTokens() {
        // Sell the tokens
        const buyTx = await wethGateway.buy(
          tradingPool.address,
          poolNftIds,
          10000000 // Will always be hiher than the actual sell price
        );
        await buyTx.wait();

        // Check that user has all the NFTs
        const nftBalances = await testNFT.balanceOf(owner.address);
        expect(nftBalances).to.equal(numNfts);
      }
    });
  }
});
