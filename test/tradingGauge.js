const { expect } = require("chai");
const load = require("../scripts/testDeploy/_loadTest.js");

describe("Trading Gauge", () => {
  load.loadTest();
  it("Should create a pool and deposit into it", async function () {});
  it("Should stage the pool LP In the gauge", async function () {});
});
