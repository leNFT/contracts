# leNFT Protocol

## Run tests

To install the project and run tests do:

```bash
npm install
npm install --save-dev @nomiclabs/hardhat-ethers 'ethers@^5.0.0'
npx hardhat test
```

Don't forget to add the necessary compiler config in `hardhat.config.js`:

```bash
module.exports = {
    defaultNetwork: "hardhat",
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
```

scripts/deployProxies.js deploys all the contracts with the correct parameterization.
