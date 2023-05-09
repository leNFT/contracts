const { expect } = require("chai");
const load = require("./helpers/_loadTest.js");

describe("Trading Gauge", () => {
  load.loadTest();
  var poolAddress;
  var tradingPool;
  var gauge;
  it("Should create a pool and deposit into it", async function () {
    // Create a pool
    const createPoolTx = await tradingPoolFactory.createTradingPool(
      testNFT.address,
      weth.address
    );

    newPoolReceipt = await createPoolTx.wait();
    const event = newPoolReceipt.events.find(
      (event) => event.event === "CreateTradingPool"
    );
    poolAddress = event.args.pool;

    console.log("Created new pool: ", poolAddress);

    // Mint 50 test tokens to the callers address
    const mintTestNFTTx = await testNFT.mint(owner.address);
    await mintTestNFTTx.wait();

    // Deposit the tokens into the pool
    const TradingPool = await ethers.getContractFactory("TradingPool");
    tradingPool = TradingPool.attach(poolAddress);
    const approveNFTTx = await testNFT.setApprovalForAll(
      wethGateway.address,
      true
    );
    await approveNFTTx.wait();
    const depositTx = await wethGateway.depositTradingPool(
      poolAddress,
      0,
      [0],
      "100000000000000",
      exponentialCurve.address,
      "0",
      "100",
      { value: "100000000000001" }
    );
    await depositTx.wait();

    // Get the token uri of the position we just deposited into
    const tokenUri = await tradingPool.tokenURI(0);
    console.log("Token URI LP:", tokenUri);
  });
  it("Should create a gauge a stake into it", async function () {
    const Gauge = await ethers.getContractFactory("TradingGauge");
    gauge = await Gauge.deploy(addressesProvider.address, poolAddress);
    await gauge.deployed();
    console.log("Gauge address: ", gauge.address);

    const setAddGaugeTx = await gaugeController.addGauge(gauge.address);
    await setAddGaugeTx.wait();
    console.log("Added Gauge to Gauge Controller.");

    // Approve NFT tx
    const approveNFTTx = await tradingPool.setApprovalForAll(
      gauge.address,
      true
    );
    await approveNFTTx.wait();

    // Deposit into gauge
    const depositInGaugeTx = await gauge.deposit(0);
    await depositInGaugeTx.wait();
    console.log("Deposited LP 0 in gauge");
  });
  it("Should lock tokens and vote for gauge", async function () {
    // Mint 10 native tokens to the callers address
    const mintNativeTokenTx = await nativeToken.mint(
      owner.address,
      "20000000000000000000"
    );
    await mintNativeTokenTx.wait();

    console.log("Minted tokens");

    // Approve tokens for use by the voting escrow contract
    const approveTokenTx = await nativeToken.approve(
      votingEscrow.address,
      "10000000000000000000"
    );
    await approveTokenTx.wait();

    //Lock 10 tokens for 100 days
    await votingEscrow.createLock(
      owner.address,
      "10000000000000000000",
      Math.floor(Date.now() / 1000) + 86400 * 100
    );
    console.log(Math.floor(Date.now() / 1000) + 86400 * 100);

    // GEt the URI for the NFT lock
    const tokenUri = await votingEscrow.tokenURI(0);
    console.log("Token URI Lock: ", tokenUri);

    // VOte for gauge
    const voteForGaugeTx = await gaugeController.vote(0, gauge.address, 5000);
    await voteForGaugeTx.wait();
  });
  it("Should claim rewards from the gauge", async function () {
    // 2 hours pass
    await ethers.provider.send("evm_increaseTime", [3600 * 12]);
    // Mine a new block
    await ethers.provider.send("evm_mine", []);

    console.log("CLAIMING REWARDS");
    // Claim rewards from gauge
    const claimRewardsTx = await gauge.claim();
    await claimRewardsTx.wait();
    console.log("Claimed rewards from gauge");

    // Find if the user received the asset
    expect(await nativeToken.balanceOf(owner.address)).to.equal(
      "12834716499999999999"
    );
  });
  it("Should unstake from the gauge", async function () {
    console.log("UNSTAKING FROM GAUGE");
    // withdraw from gauge
    const withdrawFromGaugeTx = await gauge.withdraw(0);
    await withdrawFromGaugeTx.wait();
    console.log("Withdrew LP 0 from gauge");

    // Find if the user received the asset
    expect(await tradingPool.ownerOf(0)).to.equal(owner.address);
  });
});
