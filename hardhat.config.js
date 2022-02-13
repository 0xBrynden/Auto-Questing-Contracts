/**
 * @type import('hardhat/config').HardhatUserConfig
 */
 
require('@nomiclabs/hardhat-waffle')
require('hardhat-gas-reporter');
require('solidity-coverage');
require("@nomiclabs/hardhat-etherscan");
require('dotenv').config();
 
module.exports = {
  solidity: {
    compilers: [
      {
        version: '0.8.10',
        settings: {
          optimizer: {
            enabled: true,
            runs: 200,
          },
        },
      },
      {
        version: '0.5.16',
        settings: {
          optimizer: {
            enabled: true,
            runs: 200,
          },
        },
      },
    ],
  },
  networks: {
    hardhat: {
      chainId: 1337,
      blockGasLimit: 80_000_000
    },
    harmony: {
      // url: "https://api.s0.t.hmny.io",
      url: "https://harmony-0-rpc.gateway.pokt.network",
      accounts: [process.env.PRIVATE_KEY_DEPLOYER]
    },
  },
  etherscan: {
    apiKey: {
      harmony: 'your API key'
    }
  },
  gasReporter: {
    enabled: false,
    currency: 'USD',
    gasPrice: 100,
    coinmarketcap: process.env.COINMARKETCAP,
  },
};
