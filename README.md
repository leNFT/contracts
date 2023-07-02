# leNFT Protocol

Create an `hardhat.config.js` configuration file:

```bash
require("@nomiclabs/hardhat-waffle");
require("@nomiclabs/hardhat-ethers");
require("@nomiclabs/hardhat-solhint");
require("@openzeppelin/hardhat-upgrades");
require("solidity-coverage");

module.exports = {
  defaultNetwork: "hardhat",
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

To run test coverage:

```bash
npm install
npx hardhat coverage
```

To run solhint:

```bash
npm install
npx hardhat check
```

## Audits

| Company     | Date       | Audit                                                                                                                                                                                                     |
| ----------- | ---------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Three Sigma | 30/06/2023 | [Link](https://files.gitbook.com/v0/b/gitbook-x-prod.appspot.com/o/spaces/rtUBJWIE1PXZefUCF2BX/uploads/Ygx9RXVSM1Ra3yeeS5fJ/leNFT_report_June23.pdf?alt=media&token=8a2a87bf-1f93-4b41-95ed-e571a4eb3459) |
