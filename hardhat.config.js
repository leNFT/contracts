require("@nomiclabs/hardhat-waffle");
require("@nomiclabs/hardhat-ethers");
require("@nomiclabs/hardhat-vyper");
require("@openzeppelin/hardhat-upgrades");
require("dotenv").config();

// This is a sample Hardhat task. To learn how to create your own go to
// https://hardhat.org/guides/create-task.html
task("accounts", "Prints the list of accounts", async (taskArgs, hre) => {
  const accounts = await hre.ethers.getSigners();

  for (const account of accounts) {
    console.log(account.address);
  }
});

/**
 * @type import('hardhat/config').HardhatUserConfig
 */
module.exports = {
  defaultNetwork: "hardhat",
  networks: {
    hardhat: {
      forking: {
        url: "https://mainnet.infura.io/v3/" + process.env.INFURA_API_KEY,
      },
    },
    sepolia: {
      chainId: 11155111,
      url: "https://sepolia.infura.io/v3/" + process.env.INFURA_API_KEY,
      accounts: [process.env.GOERLI_ACCOUNT_KEY],
    },
    arbitrumGoerli: {
      chainId: 421613,
      url: "https://arbitrum-goerli.infura.io/v3/" + process.env.INFURA_API_KEY,
      accounts: [process.env.GOERLI_ACCOUNT_KEY],
    },
  },
  solidity: {
    compilers: [
      {
        version: "0.8.19",
        settings: {
          viaIR: true,
          optimizer: {
            enabled: true,
            runs: 200,
            details: {
              yul: true,
            },
          },
        },
      },
      {
        version: "0.7.6",
      },
      {
        version: "0.4.18",
      },
    ],
  },
  vyper: {
    version: "0.3.1",
  },
};
