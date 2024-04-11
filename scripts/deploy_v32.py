from scripts.deploy_v3 import main as deploy_v3
from scripts.inspect import get_addresses, get_router_args
from brownie import ZERO_ADDRESS, AaveV3HoldingsOracle
from brownie.network import Chain, accounts

# Make sure you have run the following as well once before you run this script:
# npm install
# npm hardhat compile

# NOTE: before you run this set your chainId in the hardhat.config.js to the following
"""
module.exports = {
  defaultNetwork: "hardhat",
  chainId: 42161,
  networks: {
    hardhat: {
      chainId: 42161,
      hardfork: "london",
      initialBaseFeePerGas: 0,
      throwOnTransactionFailures: true,
      throwOnCallFailures: true,
    },
  }
}
"""

chain = Chain()

def main():
  (_, notional, _, router, *_) = get_addresses()
  deploy_v3()

