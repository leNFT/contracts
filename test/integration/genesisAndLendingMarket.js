const { expect } = require("chai");
const { ethers } = require("hardhat");
const { BigNumber } = require("ethers");
const load = require("../helpers/_loadTest.js");
const weightedPoolFactoryABI = require("../../scripts/balancer/weightedPoolFactoryABI.json");
const vaultABI = require("../../scripts/balancer/vaultABI.json");
const { getPriceSig } = require("../helpers/getPriceSig.js");
const { time } = require("@nomicfoundation/hardhat-network-helpers");

describe("Genesis NFT & Lending Market", function () {
  load.loadTest(true);

  before(async function () {
    const vaultAddress = "0xBA12222222228d8Ba445958a75a0704d566BF2C8";
    const queryAddress = "0xE39B5e3B6D74016b2F6A9673D7d7493B6DF549d5";
    const poolFactoryAddress = "0x5Dd94Da3644DDD055fcf6B3E1aa310Bb7801EB8b";

    const factoryContract = await ethers.getContractAt(
      weightedPoolFactoryABI,
      poolFactoryAddress
    );

    var tokenAddresses;
    var tokenWeights;
    var maxAmountsIn;

    if (wethAddress < nativeToken.address) {
      tokenAddresses = [wethAddress, nativeToken.address];
      tokenWeights = ["200000000000000000", "800000000000000000"];
      maxAmountsIn = [
        BigNumber.from(ethers.utils.parseEther("0.5")),
        BigNumber.from(ethers.utils.parseEther("20000")),
      ];
    } else {
      tokenAddresses = [nativeToken.address, wethAddress];
      tokenWeights = ["800000000000000000", "200000000000000000"];
      maxAmountsIn = [
        BigNumber.from(ethers.utils.parseEther("20000")),
        BigNumber.from(ethers.utils.parseEther("0.5")),
      ];
    }

    console.log("Deploying Balancer pool...");
    console.log("LE address: ", nativeToken.address);
    console.log("WETH address: ", wethAddress);
    const createTx = await factoryContract.create(
      "Balancer Pool 80 LE 20 WETH",
      "B-80LE-20WETH",
      tokenAddresses,
      tokenWeights,
      [ethers.constants.AddressZero, ethers.constants.AddressZero],
      "2500000000000000",
      "0xba1ba1ba1ba1ba1ba1ba1ba1ba1ba1ba1ba1ba1b"
    );
    const createTxReceipt = await createTx.wait();
    const poolId = createTxReceipt.logs[1].topics[1];
    const poolAddress = poolId.slice(0, 42);

    const balancerDetails = {
      poolId: poolId,
      pool: poolAddress,
      vault: vaultAddress,
      queries: queryAddress,
    };

    console.log("Balancer details: ", balancerDetails);
    const setBalancerDetailsTx = await genesisNFT.setBalancerDetails(
      balancerDetails
    );
    await setBalancerDetailsTx.wait();
    console.log("Set Balancer details");

    // Deposit in the balancer pool
    const vault = await ethers.getContractAt(vaultABI, vaultAddress);

    // Mint weth and LE and approve them to be used by the vault
    const mintWETHTx = await weth.deposit({
      value: ethers.utils.parseEther("0.5"),
    });
    await mintWETHTx.wait();
    const approveWETHTx = await weth.approve(
      vault.address,
      ethers.utils.parseEther("0.5")
    );
    await approveWETHTx.wait();

    const approveLETx = await nativeToken.approve(
      vault.address,
      ethers.utils.parseEther("20000")
    );
    await approveLETx.wait();
    const userData = ethers.utils.defaultAbiCoder.encode(
      ["uint8", "uint256[]"],
      [0, maxAmountsIn]
    );

    // Deposit in the vault so the genesis can operate normally
    const depositPoolTx = await vault.joinPool(
      poolId,
      owner.address,
      owner.address,
      {
        assets: tokenAddresses,
        maxAmountsIn: maxAmountsIn,
        userData: userData,
        fromInternalBalance: false,
      }
    );
    await depositPoolTx.wait();

    // Take a snapshot before the tests start
    snapshotId = await ethers.provider.send("evm_snapshot", []);
  });

  beforeEach(async function () {
    // Restore the blockchain state to the snapshot before each test
    await ethers.provider.send("evm_revert", [snapshotId]);

    // Take a snapshot before the tests start
    snapshotId = await ethers.provider.send("evm_snapshot", []);
  });

  it("Should be able to borrow from the market using the genesis NFT", async function () {
    // Mint a genesis NFT
    const locktime = 60 * 60 * 24 * 120; // 120 days

    // Mint Genesis NFT
    const mintGenesisNFTTx = await genesisNFT.mint(locktime, 1, {
      value: await genesisNFT.getPrice(), // 0.35 ETH
    });
    await mintGenesisNFTTx.wait();

    // Deposit in lending pool
    const createLendingPoolTx = await lendingMarket.createLendingPool(
      testNFT.address,
      weth.address
    );
    await createLendingPoolTx.wait();
    const depositTx = await wethGateway.depositLendingPool(
      await lendingMarket.getLendingPool(testNFT.address, weth.address),
      { value: ethers.utils.parseEther("10") }
    );
    await depositTx.wait();

    // Mint a test NFT
    const mintTestNftTx = await testNFT.mint(owner.address);
    await mintTestNftTx.wait();

    // Approve assets to be used by the lending market
    const approveNftTx = await testNFT.approve(lendingMarket.address, 0);
    await approveNftTx.wait();

    const priceSig = getPriceSig(
      testNFT.address,
      [0],
      ethers.utils.parseEther("80"), //Price of 80 ETH
      await time.latest(),
      nftOracle.address
    );

    const borrowTx = await lendingMarket.borrow(
      owner.address,
      weth.address,
      ethers.utils.parseEther("1"),
      testNFT.address,
      [0],
      1,
      priceSig.request,
      priceSig
    );
    await borrowTx.wait();

    // Check if the Genesis NFT is locked
    expect(await genesisNFT.getLockedState(1)).to.equal(true);
  });
  it("Should unlock a genesis NFT after a liquidation has been claimed", async function () {
    // Mint a genesis NFT
    const locktime = 60 * 60 * 24 * 120; // 120 days

    // Mint Genesis NFT
    const mintGenesisNFTTx = await genesisNFT.mint(locktime, 1, {
      value: await genesisNFT.getPrice(), // 0.35 ETH
    });
    await mintGenesisNFTTx.wait();

    // Deposit in lending pool
    const createLendingPoolTx = await lendingMarket.createLendingPool(
      testNFT.address,
      weth.address
    );
    await createLendingPoolTx.wait();
    const depositTx = await wethGateway.depositLendingPool(
      await lendingMarket.getLendingPool(testNFT.address, weth.address),
      { value: ethers.utils.parseEther("10") }
    );
    await depositTx.wait();

    // Mint a test NFT
    const mintTestNftTx = await testNFT.mint(owner.address);
    await mintTestNftTx.wait();

    // Approve assets to be used by the lending market
    const approveNftTx = await testNFT.approve(lendingMarket.address, 0);
    await approveNftTx.wait();

    const priceSig = getPriceSig(
      testNFT.address,
      [0],
      ethers.utils.parseEther("80"), //Price of 80 ETH
      await time.latest(),
      nftOracle.address
    );

    const borrowTx = await lendingMarket.borrow(
      owner.address,
      weth.address,
      ethers.utils.parseEther("1"),
      testNFT.address,
      [0],
      1,
      priceSig.request,
      priceSig
    );
    await borrowTx.wait();

    const priceSig2 = getPriceSig(
      testNFT.address,
      [0],
      ethers.utils.parseEther("0.08"), // 100x lower than the borrow price
      await time.latest(),
      nftOracle.address
    );

    // Get WETH from the weth contract
    const getWETHTx = await weth.deposit({
      value: ethers.utils.parseEther("0.07"),
    });
    await getWETHTx.wait();

    // Approve the WETH to be used by the lending market
    const approveWETHTx = await weth.approve(
      lendingMarket.address,
      ethers.utils.parseEther("0.07")
    );
    await approveWETHTx.wait();

    const createLiquidationAuctionTx =
      await lendingMarket.createLiquidationAuction(
        owner.address,
        0,
        ethers.utils.parseEther("0.07"),
        priceSig2.request,
        priceSig2
      );
    await createLiquidationAuctionTx.wait();

    // Make the auction end (24 hours)
    await time.increase(60 * 60 * 24);

    // Genesis NFT should be locked
    expect(await genesisNFT.getLockedState(1)).to.equal(true);

    const claimTx = await lendingMarket.claimLiquidation(0);
    await claimTx.wait();

    // Genesis NFT should be unlocked
    expect(await genesisNFT.getLockedState(1)).to.equal(false);
  });
});
