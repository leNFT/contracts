const { expect } = require("chai");
const load = require("../helpers/_loadTest.js");
const { ethers } = require("hardhat");
const { beforeEach } = require("mocha");
const { time } = require("@nomicfoundation/hardhat-network-helpers");
const { BigNumber } = require("ethers");
const { isValidJSON, isValidSVG } = require("../helpers/validateFormats.js");
const weightedPoolFactoryABI = require("../../scripts/balancer/weightedPoolFactoryABI.json");
const vaultABI = require("../../scripts/balancer/vaultABI.json");
const { getPriceSig } = require("../helpers/getPriceSig.js");

describe("Borrow using Genesis NFT", function () {
  load.loadTest(true);

  // Setup the genesis NFT
  before(async function () {
    const vaultAddress = "0xBA12222222228d8Ba445958a75a0704d566BF2C8";
    const queryAddress = "0xE39B5e3B6D74016b2F6A9673D7d7493B6DF549d5";
    const poolFactoryAddress = "0x897888115Ada5773E02aA29F775430BFB5F34c51";

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
      "0xba1ba1ba1ba1ba1ba1ba1ba1ba1ba1ba1ba1ba1b",
      ethers.utils.formatBytes32String("leNFT")
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
  });

  it("Create NFT asset 1", async function () {
    // Mint 2 NFT collaterals
    const mintTestNftTx = await testNFT.mint(owner.address);
    const tokenIDReceipt = await mintTestNftTx.wait();
    const event = tokenIDReceipt.events.find((event) => event.event === "Mint");
    tokenID1 = event.args.tokenId.toNumber();

    // Find if the NFT was minted accordingly
    expect(await testNFT.ownerOf(tokenID1)).to.equal(owner.address);
  });
  it("Create NFT asset 2", async function () {
    // Mint 2 NFT collaterals
    const mintTestNftTx = await testNFT.mint(owner.address);
    const tokenIDReceipt = await mintTestNftTx.wait();
    const event = tokenIDReceipt.events.find((event) => event.event === "Mint");
    tokenID2 = event.args.tokenId.toNumber();

    // Find if the NFT was minted accordingly
    expect(await testNFT.ownerOf(tokenID2)).to.equal(owner.address);
  });
  it("Deposit underlying to the lending pool", async function () {
    const createLendingPoolTx = await lendingMarket.createLendingPool(
      testNFT.address,
      weth.address
    );
    await createLendingPoolTx.wait();
    const depositTx = await wethGateway.depositLendingPool(
      await lendingMarket.getLendingPool(testNFT.address, weth.address),
      { value: ethers.utils.parseEther("2") }
    );
    await depositTx.wait();
  });
  it("Should mint a Genesis NFT", async function () {
    const locktime = 60 * 60 * 24 * 120; // 120 days

    // Mint Genesis NFT
    const mintGenesisNFTTx = await genesisNFT.mint(locktime, 1, {
      value: await genesisNFT.getPrice(), // 0.35 ETH
    });
    await mintGenesisNFTTx.wait();

    // Find if the NFT was minted accordingly
    expect(await genesisNFT.ownerOf(1)).to.equal(owner.address);
  });
  it("Borrow using NFT asset as collateral", async function () {
    // Approve assets to be used by the lending market
    const approveNftTx1 = await testNFT.approve(wethGateway.address, tokenID1);
    await approveNftTx1.wait();
    const approveNftTx2 = await testNFT.approve(wethGateway.address, tokenID2);
    await approveNftTx2.wait();

    const priceSig = getPriceSig(
      testNFT.address,
      [tokenID1, tokenID2],
      ethers.utils.parseEther("80"), //Price of 80 ETH
      "1694784579",
      nftOracle.address
    );
    console.log("Got price sig for: ", [tokenID1, tokenID2]);
    // Ask the market to borrow underlying using the collateral
    const balanceBeforeBorrow = await owner.getBalance();
    console.log("Balance before borrow: ", balanceBeforeBorrow.toString());

    // Add the weth gateway as a loan operator
    const addLoanOperatorTx = await genesisNFT.setLoanOperatorApproval(
      wethGateway.address,
      true
    );
    await addLoanOperatorTx.wait();

    const borrowTx = await wethGateway.borrow(
      ethers.utils.parseEther("1"),
      testNFT.address,
      [tokenID1, tokenID2],
      1,
      priceSig.request,
      priceSig
    );
    const receipt = await borrowTx.wait();
    console.log("Gas used: ", receipt.gasUsed.toString());
    const balanceAfterBorrow = await owner.getBalance();
    console.log("Balance after borrow: ", balanceAfterBorrow.toString());
    const gasUsedETH = receipt.effectiveGasPrice * receipt.gasUsed;
    console.log("Gas used in ETH: ", gasUsedETH.toString());

    // Find if the protocol received the asset
    expect(await testNFT.ownerOf(tokenID1)).to.equal(lendingMarket.address);
    expect(await testNFT.ownerOf(tokenID2)).to.equal(lendingMarket.address);

    // Find if the Genesis NFT is locked
    expect(await genesisNFT.getLockedState(1)).to.equal(true);
  });
  it("Throw an error if we try to use the genesis NFT again", async function () {
    // Mint 1 NFT collaterals
    const mintTestNftTx = await testNFT.mint(owner.address);
    const tokenIDReceipt = await mintTestNftTx.wait();
    const event = tokenIDReceipt.events.find((event) => event.event === "Mint");
    tokenID3 = event.args.tokenId.toNumber();

    const approveNftTx = await testNFT.approve(wethGateway.address, tokenID3);
    await approveNftTx.wait();

    const priceSig = getPriceSig(
      testNFT.address,
      [tokenID3],
      ethers.utils.parseEther("80"),
      "1694784579",
      nftOracle.address
    );

    await expect(
      wethGateway.borrow(
        ethers.utils.parseEther("1"),
        testNFT.address,
        [tokenID3],
        1,
        priceSig.request,
        priceSig
      )
    ).to.be.revertedWith("VL:VB:GENESIS_LOCKED");
  });
  it("Repay borrowed amount", async function () {
    // Get loan debt
    const loanDebt = await loanCenter.getLoanDebt(0);

    const repayTx = await wethGateway.repay(0, {
      value: loanDebt,
    });
    await repayTx.wait();
    expect(await testNFT.ownerOf(tokenID1)).to.equal(owner.address);
    expect(await testNFT.ownerOf(tokenID2)).to.equal(owner.address);

    // Find if the Genesis NFT is locked (should be unlocked)
    expect(await genesisNFT.getLockedState(1)).to.equal(false);
  });
  it("Repay 1st borrowed amount again", async function () {
    // Get loan debt
    const loanDebt = await loanCenter.getLoanDebt(0);

    // Expect this transaction to revert since this was already repaid
    expect(
      wethGateway.repay(0, {
        value: loanDebt,
      })
    ).to.be.revertedWith("VL:VR:LOAN_NOT_FOUND");
  });
});
