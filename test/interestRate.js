const { expect } = require("chai");
const load = require("../scripts/testDeploy/_loadTest.js");

describe("InterestRate", function () {
  load.loadTest();
  it("Calculates the correct interest rate", async function () {
    // Borrow rate for the optimum utilization of 80%
    const borrowRate = await interestRate.calculateBorrowRate("20", "80");

    // Find if the NFT was minted accordingly
    expect(borrowRate).to.equal(3000);
  });
});
