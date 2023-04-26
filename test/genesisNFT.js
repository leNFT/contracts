const { expect } = require("chai");
const load = require("../scripts/testDeploy/_loadTest.js");
const weightedPoolFactoryABI = require("../scripts/balancer/weightedPoolFactoryABI.json");

// Should be used in a forked mainnet/sepolia env so to use the balancer pool
describe("GenesisNFT", function () {
  load.loadTest();
  it("Set the balancer details", async function () {
    const vaultAddress = "0xBA12222222228d8Ba445958a75a0704d566BF2C8";
    const queryAddress = "0xE39B5e3B6D74016b2F6A9673D7d7493B6DF549d5";
    const poolFactoryAddress = "0x5Dd94Da3644DDD055fcf6B3E1aa310Bb7801EB8b";

    const factoryContract = await ethers.getContractAt(
      weightedPoolFactoryABI,
      poolFactoryAddress
    );

    var tokenAddresses;
    var tokenWeights;

    if (wethAddress < nativeToken.address) {
      tokenAddresses = [wethAddress, nativeToken.address];
      tokenWeights = ["200000000000000000", "800000000000000000"];
    } else {
      tokenAddresses = [nativeToken.address, wethAddress];
      tokenWeights = ["800000000000000000", "200000000000000000"];
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
  });
  it("Should mint a token", async function () {
    // Mint Genesis NFT
    const mintGenesisNFTTx = await genesisNFT.mint(2592000, 10, {
      value: "3000000000000000000", // 0.3 ETH * 10
    });
    await mintGenesisNFTTx.wait();

    // Find if the NFT was minted
    expect(await genesisNFT.ownerOf(1)).to.equal(owner.address);

    // Print the NFT's token URI
    console.log("Token URI: ", await genesisNFT.tokenURI(1));
  });
  it("Should burn a token", async function () {
    const lpValue = await genesisNFT.callStatic.getLPValueInLE([1, 2]);
    console.log("LP value: ", lpValue.toString(), "LE");

    await network.provider.send("evm_increaseTime", [2592000]);
    await network.provider.send("evm_mine");
    // Increase time and Burn Genesis NFT
    const burnGenesisNFTTx = await genesisNFT.burn([1, 2]);
    await burnGenesisNFTTx.wait();

    // Find if we received the expected amount of LE
    expect(await nativeToken.balanceOf(owner.address)).to.equal(lpValue);
  });
});
