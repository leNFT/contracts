const { expect } = require("chai");
const load = require("../helpers/_loadTest.js");
const { ethers } = require("hardhat");
const { beforeEach } = require("mocha");
const { time } = require("@nomicfoundation/hardhat-network-helpers");
const { BigNumber } = require("ethers");
const { isValidJSON, isValidSVG } = require("../helpers/validateFormats.js");
const weightedPoolFactoryABI = require("../../scripts/balancer/weightedPoolFactoryABI.json");
const vaultABI = require("../../scripts/balancer/vaultABI.json");

describe("GenesisNFT", () => {
  load.loadTestAlways(true);

  // Set the balancer pool details before each test
  beforeEach(async function () {
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

    const mintNativeToken = await nativeToken.mint(
      owner.address,
      ethers.utils.parseEther("20000")
    );
    await mintNativeToken.wait();

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

  // it("Should mint a Genesis NFT", async function () {
  //   const locktime = 60 * 60 * 24 * 120; // 120 days
  //   const nativeTokenReward = await genesisNFT.getCurrentLEReward(1, locktime);

  //   // Save dev balance before
  //   const devBalanceBefore = await ethers.provider.getBalance(address1.address);

  //   // Mint Genesis NFT
  //   const mintGenesisNFTTx = await genesisNFT.mint(locktime, 1, {
  //     value: await genesisNFT.getPrice(), // 0.35 ETH
  //   });
  //   await mintGenesisNFTTx.wait();

  //   // Check if dev received the ETH minus the gas cost
  //   expect(await ethers.provider.getBalance(address1.address)).to.equal(
  //     BigNumber.from(ethers.utils.parseEther("0.15")).add(devBalanceBefore)
  //   );

  //   // Save the timestamp of the mint
  //   const mintTimestamp = await time.latest();

  //   // Find if the NFT was minted
  //   expect(await genesisNFT.ownerOf(1)).to.equal(owner.address);

  //   // Should get the locked state of the NFT
  //   expect(await genesisNFT.getLockedState(1)).to.equal(false);

  //   // SHould get the right unlock timestamp
  //   expect(await genesisNFT.getUnlockTimestamp(1)).to.equal(
  //     BigNumber.from(mintTimestamp).add(locktime)
  //   );

  //   // THe valur of the LP associated with the NFT should be higher than 0
  //   expect(await genesisNFT.callStatic.getLPValueInLE([1])).to.be.gt(0);

  //   // The mint count should be 1
  //   expect(await genesisNFT.mintCount()).to.equal(1);

  //   // Find if the user received has a an LE lock
  //   expect(await votingEscrow.balanceOf(owner.address)).to.equal(1);

  //   // Find if the received lock is for the right amount of LE
  //   expect((await votingEscrow.getLock(0)).amount).to.equal(nativeTokenReward);
  // });
  it("Should burn a Genesis NFT", async function () {
    const locktime = 60 * 60 * 24 * 120; // 120 days
    // Mint 2 Genesis NFT so the pool has enough liquidity to exit
    const mintGenesisNFTTx = await genesisNFT.mint(locktime, 1, {
      value: await genesisNFT.getPrice(), // 0.35 ETH
    });
    await mintGenesisNFTTx.wait();

    // Pass the entire locktime
    await time.increase(locktime);

    // Get the LE balance of the user
    const leBalanceBefore = await nativeToken.balanceOf(owner.address);

    // Get the LP Value of the NFT
    const lpValue = await genesisNFT.callStatic.getLPValueInLE([1]);

    // Burn the NFT
    const burnGenesisNFTTx = await genesisNFT.burn([1]);
    await burnGenesisNFTTx.wait();

    // Find if the NFT was burnt
    expect(await genesisNFT.balanceOf(owner.address)).to.equal(0);

    // Find if the user received the LP withdrawal
    expect(await nativeToken.balanceOf(owner.address)).to.equal(
      BigNumber.from(leBalanceBefore).add(lpValue)
    );
  });
  it("Should make sure the Genesis NFT has a valid token URI", async function () {
    const locktime = 60 * 60 * 24 * 120; // 120 days

    // Mint Genesis NFT
    const mintGenesisNFTTx = await genesisNFT.mint(locktime, 1, {
      value: await genesisNFT.getPrice(), // 0.35 ETH * 10
    });
    await mintGenesisNFTTx.wait();

    // Get the token URI
    const tokenURI = await genesisNFT.tokenURI(1);

    const base64Data = tokenURI.split("base64,")[1]; // Extract the base64 content
    console.log(base64Data);
    const decodedDataBuffer = ethers.utils.base64.decode(base64Data);
    const decodedData = Buffer.from(decodedDataBuffer).toString("utf-8"); // Convert ArrayBuffer to a UTF-8 string using Buffer.from()

    // Check if the token URI is valid JSON
    expect(isValidJSON(decodedData)).to.equal(true);
  });
  it("Should make sure the Genesis NFT has a valid token SVG", async function () {
    const locktime = 60 * 60 * 24 * 120; // 120 days.

    // Mint Genesis NFT
    const mintGenesisNFTTx = await genesisNFT.mint(locktime, 1, {
      value: await genesisNFT.getPrice(), // 0.35 ETH * 10
    });
    await mintGenesisNFTTx.wait();

    // Get the token URI
    const svg = await genesisNFT.svg(1);
    const decodedData = ethers.utils.toUtf8String(svg); // Convert the hex string to a UTF-8 string

    // Check if the svg is valid
    expect(isValidSVG(decodedData)).to.equal(true);
  });
});