# leNFT Protocol

## Run tests

To install the project and run tests do:

```bash
npm install
npx hardhat test
```

Don't forget to add the necessary compiler config in `hardhat.config.js`:

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
        version: "0.4.18",
      },
    ],
  },
};

```

Test are done in a forked mainnet enviroment so you'll also need a .env file with an Infura API Key.

```bash
INFURA_API_KEY="YOUR_API_KEY"

```

Use the following script to deploy all the contracts with the correct parameterization:

```bash
scripts/deployProxies.js

```
