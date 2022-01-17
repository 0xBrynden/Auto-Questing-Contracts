/**
 * @type import('hardhat/config').HardhatUserConfig
 */
 
require('@nomiclabs/hardhat-waffle')
require('hardhat-gas-reporter');
require('solidity-coverage');
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
    //mainnet: {
    //  url: process.env.INFURA_URL,
    //  accounts: [`0x${process.env.PRIVATE_KEY}`]
    //}
  },
  gasReporter: {
    enabled: false,
    currency: 'USD',
    gasPrice: 100,
    coinmarketcap: process.env.COINMARKETCAP,
  },
};
