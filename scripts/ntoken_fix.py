from scripts.inspect import get_addresses, get_router_args
from brownie import (
    Router, BatchAction, AccountAction, nTokenMintAction,
    nTokenRedeemAction, FreeCollateralExternal, TradingAction,
    SettleAssetsExternal
)

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

def main():
    (_, notional, _, router, *_) = get_addresses()
    FreeCollateralExternal.at("0x50DA106863b47882e4eEfaE2303770019648Bd6f")
    SettleAssetsExternal.at("0x65BA68d83F74D60c9e2270b05A2627a7C34F4bC4")
    TradingAction.at("0xcC7cdD6a8655a70054de07D6c89996e371961Ecb")
    nTokenMint = nTokenMintAction.deploy({"from": notional.owner()})
    nTokenRedeem = nTokenRedeemAction.deploy({"from": notional.owner()})
    ac = AccountAction.deploy({"from": notional.owner()})
    ba = BatchAction.deploy({"from": notional.owner()})

    assert ba.getLibInfo()[4] == nTokenMint.address
    assert ba.getLibInfo()[5] == nTokenRedeem.address

    router_args = get_router_args(router)
    router_args[4] = ba.address
    router_args[5] = ac.address
    router = Router.deploy(router_args, {"from": notional.owner()})

    notional.upgradeTo(router, {"from": notional.owner()})

