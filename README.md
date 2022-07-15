# leNFT Protocol

## Run tests

To install the project and run tests do:

```bash
npm install
npm install --save-dev @nomiclabs/hardhat-ethers 'ethers@^5.0.0'
npx hardhat test
```

Don't forget to update the solidity version in `hardhat.config.js`:

```bash
module.exports = {
    defaultNetwork: "hardhat",
    solidity: "0.8.15",
};
```
