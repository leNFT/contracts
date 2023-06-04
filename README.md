# leNFT Protocol

Create an `hardhat.config.js` configuration file:

```bash
require("@nomiclabs/hardhat-waffle");
require("@nomiclabs/hardhat-ethers");
require("@nomiclabs/hardhat-vyper");
require("@nomiclabs/hardhat-solhint");
require("@openzeppelin/hardhat-upgrades");
require("dotenv").config();

module.exports = {
  defaultNetwork: "hardhat",
  networks: {
    hardhat: {
      forking: {
        url: "https://mainnet.infura.io/v3/" + process.env.INFURA_API_KEY,
      },
    },
  },
  solidity: {
    compilers: [
      {
        version: "0.8.19",
        settings: {
          viaIR: false,
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
        version: "0.4.18",
      },
    ],
  },
};

```

Some tests are performed in a forked mainnet environment, so you'll also need a .env file with an Infura API Key.

```bash
INFURA_API_KEY="YOUR_API_KEY"

```

To run tests:

```bash
npm install
npx hardhat test
```

...or to run test coverage:

```bash
npm install
npx hardhat coverage
```
