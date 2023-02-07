const { expect } = require("chai");
const load = require("../scripts/testDeploy/_loadTest.js");

describe("GenesisNFT", function () {
  load.loadTest();

  it("Should create and set the incentivized trading pool", async function () {
    const Pool = await ethers.getContractFactory("CurvePool");
    const pool = await Pool.deploy();
    await pool.deployed();

    // Init pool
    const initPoolTx = await pool.initialize(
      "leNFT",
      "LE",
      [
        "0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE", // Burn address
        nativeToken.address,
        ethers.constants.AddressZero,
        ethers.constants.AddressZero,
      ],
      [
        ethers.utils.parseUnits("1", 18),
        ethers.utils.parseUnits("1", 18),
        0,
        0,
      ],
      10000,
      300
    );
    await initPoolTx.wait();

    // Set trusted price source
    const setIncentivizedPoolTx = await genesisNFT.setTradingPool(pool.address);
    await setIncentivizedPoolTx.wait();
  });
  it("Should mint a token", async function () {
    // Mint Genesis NFT
    const mintGenesisNFTTx = await genesisNFT.mint(2592000, "", {
      value: "3000000000000000",
    });
    await mintGenesisNFTTx.wait();

    // Find if the NFT was minted
    expect(await genesisNFT.ownerOf(1)).to.equal(owner.address);
  });
  it("Should burn a token", async function () {
    // Increase time and Burn Genesis NFT
    await network.provider.send("evm_increaseTime", [2592000]);
    await network.provider.send("evm_mine");
    const balanceBefore = await owner.getBalance();
    const burnGenesisNFTTx = await genesisNFT.burn(1);
    await burnGenesisNFTTx.wait();
    const balanceAfter = await owner.getBalance();

    // Find if the NFT was minted
    expect(balanceAfter.sub(balanceBefore).toString()).to.equal(
      "199798575613703807"
    );
  });
});
