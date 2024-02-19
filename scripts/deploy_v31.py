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

  # List External Rewarders
  ethHoldingsOracle = AaveV3HoldingsOracle.deploy(
    notional.address, ZERO_ADDRESS,
    "0x794a61358D6845594F94dc1DB02A252b5b4814aD",
    "0xe50fA9b3c56FfB159cB0FCA61F5c9D750e8128c8", # aETH
    "0x69FA688f1Dc47d4B5d8029D5a35FB7a548310654",
    {"from": accounts[0]}
  )
  usdcHoldingsOracle = AaveV3HoldingsOracle.deploy(
    notional.address,
    "0xaf88d065e77c8cC2239327C5EDb3A432268e5831",
    "0x794a61358D6845594F94dc1DB02A252b5b4814aD",
    "0x724dc807b04555b71ed48a6896b6F41593b8C637", # aUSDC
    "0x69FA688f1Dc47d4B5d8029D5a35FB7a548310654",
    {"from": accounts[0]}
  )


  notional.setRebalancingBot(accounts[0], {'from': notional.owner()})

  # ETH
  log_rebalance(ethHoldingsOracle, 1e18)
  # Set a cap on the deposits
  ethHoldingsOracle.setMaxExternalAvailable(1e18, {"from": notional.owner()})

  notional.updatePrimeCashHoldingsOracle(1, ethHoldingsOracle, {"from": notional.owner()})
  notional.setRebalancingCooldown(1, 360, {"from": notional.owner()})

  # NOTE: this will initiate the first rebalance
  notional.setRebalancingTargets(
    1, [("0xe50fA9b3c56FfB159cB0FCA61F5c9D750e8128c8", 85, 120)], {"from": notional.owner()}
  )
  log_rebalance(ethHoldingsOracle, 1e18)

  # USDC
  # notional.updatePrimeCashHoldingsOracle(3, usdcHoldingsOracle, {"from": notional.owner()})
  # notional.setRebalancingCooldown(3, 360, {"from": notional.owner()})
  # notional.setRebalancingTargets(
  #   3, [("0x724dc807b04555b71ed48a6896b6F41593b8C637", 85, 120)], {"from": notional.owner()}
  # )

def log_rebalance(holdingsOracle, precision):
  print("Total Underlying: ", holdingsOracle.getTotalUnderlyingValueView()['nativePrecision'] / precision)
  print("Total Holdings: ", holdingsOracle.holdingValuesInUnderlying()[0] / precision)
  print("Max Available For Withdraw: ", holdingsOracle.getOracleData()['externalUnderlyingAvailableForWithdraw'] / precision)
  print("Max Deposit: ", holdingsOracle.getOracleData()['maxExternalDeposit'])
