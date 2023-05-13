const { expect } = require("chai");
const { time } = require("@nomicfoundation/hardhat-network-helpers");
const { ethers } = require("hardhat");
const { BigNumber } = require("ethers");
const load = require("../helpers/_loadTest.js");
const { getPriceSig, priceSigner } = require("../helpers/getPriceSig.js");

describe("NFTOracle", function () {
  let NFTOracle, nftOracle, owner;
  const testAddress = "0x853d955aCEf822Db058eb8505911ED77F175b99e";

  beforeEach(async () => {
    NFTOracle = await ethers.getContractFactory("NFTOracle");
    [owner] = await ethers.getSigners();
    nftOracle = await NFTOracle.deploy();
    await nftOracle.deployed();
  });

  it("Should be able to add a price signer", async function () {
    expect(await nftOracle.isTrustedSigner(owner.address)).to.equal(false);
    const tx = await nftOracle.setTrustedPriceSigner(owner.address, true);
    await tx.wait();

    expect(await nftOracle.isTrustedSigner(owner.address)).to.equal(true);
  });
  it("Should be able to get the ETH price for a token", async function () {
    const tx = await nftOracle.setTrustedPriceSigner(priceSigner, true);
    await tx.wait();

    // Get the price signature for the NFT
    const priceSig = getPriceSig(
      testAddress,
      [0],
      ethers.utils.parseEther("0.08"), //Price of 0.08 ETH
      await time.latest(),
      nftOracle.address
    );

    // Get the on-chain price
    const price = await nftOracle.getTokensETHPrice(
      testAddress,
      [0],
      priceSig.request,
      priceSig
    );

    expect(price).to.equal(ethers.utils.parseEther("0.08"));
  });
});
