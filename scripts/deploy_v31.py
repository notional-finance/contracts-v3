from scripts.deploy_v3 import main as deploy_v3
from scripts.inspect import get_addresses, get_router_args
from brownie.network import Chain

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

  # Update mint deviation limit
  for id in range(1, 10):
    nToken = notional.nTokenAddress(id)
    params = notional.getNTokenAccount(nToken)['nTokenParameters']
    notional.updateTokenCollateralParameters(
      id,
      params[4],
      params[3],
      params[2],
      params[1],
      params[0],
      40, # 2% in 5bps increments
      {'from': notional.owner()}
    )

  # Update prime debt limits
  for id in range(1, notional.getMaxCurrencyId() + 1):
    curve = notional.getPrimeInterestRateCurve(id)
    maxSupply = notional.getPrimeFactors(id, chain.time())['maxUnderlyingSupply']
    debtCap = curve['kinkUtilization2'] * 100 / 1e9
    notional.setMaxUnderlyingSupply(id, maxSupply, debtCap, {"from": notional.owner()})
