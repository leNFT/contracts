const { expect } = require("chai");
const load = require("../scripts/testDeploy/_loadTest.js");

describe("GenesisNFT", function () {
  load.loadTest();
  it("Should create the genesis reserve", async function () {
    // Create Market
    const createReserveTx = await market.createReserve(
      genesisNFT.address,
      weth.address
    );
    await createReserveTx.wait();
    const setGenesisMintReserveTx = await genesisNFT.setMintReserve(
      await market.getReserve(genesisNFT.address, weth.address)
    );
    await setGenesisMintReserveTx.wait();
  });
  it("Should mint a token", async function () {
    const distributeRewardsTx =
      await nativeTokenVault.distributeStakingRewards();
    await distributeRewardsTx.wait();

    // Mint Genesis NFT
    const mintGenesisNFTTx = await genesisNFT.mint(2592000, "", {
      value: "300000000000000000",
    });
    await mintGenesisNFTTx.wait();

    // Find if the NFT was minted
    expect(await genesisNFT.ownerOf(0)).to.equal(owner.address);
  });
  it("Should burn a token", async function () {
    // Increase time and Burn Genesis NFT
    await network.provider.send("evm_increaseTime", [2592000]);
    await network.provider.send("evm_mine");
    const balanceBefore = await owner.getBalance();
    const burnGenesisNFTTx = await genesisNFT.burn(0);
    await burnGenesisNFTTx.wait();
    const balanceAfter = await owner.getBalance();

    // Find if the NFT was minted
    expect(balanceAfter.sub(balanceBefore).toString()).to.equal(
      "199848172441786380"
    );
  });
});
