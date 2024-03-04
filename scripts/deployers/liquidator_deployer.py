import json

from brownie import Contract, FlashLiquidator, accounts, interface
from brownie.network import Chain
from scripts.inspect import get_addresses

DEPLOYER = "0x8B64fA5Fd129df9c755eB82dB1e16D6D0Bdf5Bc3"
FLASH_LENDER = "0x87870Bca3F3fD6335C3F4ce8392D69350B4fA4E2"
chain = Chain()


def main():
    (addresses, notional, *_) = get_addresses()
    deployer = accounts.load("MAINNET_DEPLOYER")

    liquidator = FlashLiquidator.deploy(
        notional.address,
        addresses["aaveLendingPool"],
        addresses["tokens"]["WETH"]["address"],
        deployer,
        addresses["tradingModule"],
        {"from": deployer},
    )

    maxCurrencyId = notional.getMaxCurrencyId()
    tradingModule = Contract.from_abi(
        "trading", addresses["tradingModule"], interface.ITradingModule.abi
    )
    liquidator.enableCurrencies([i for i in range(1, maxCurrencyId + 1)], {"from": deployer})

    batchBase = {
        "version": "1.0",
        "chainId": "42161",
        "createdAt": 1692567274357,
        "meta": {"name": "Transactions Batch", "description": "", "txBuilderVersion": "1.16.1"},
        "transactions": [],
    }
    approvals = []
    for i in range(1, maxCurrencyId + 1):
        underlying = notional.getCurrency(i)["underlyingToken"]["tokenAddress"]
        approvals.append(
            {
                "to": tradingModule.address,
                "value": "0",
                "data": tradingModule.setTokenPermissions.encode_input(
                    liquidator, underlying, (True, 8, 15)
                ),
                "contractMethod": {"inputs": [], "name": "fallback", "payable": True},
                "contractInputsValues": None,
            }
        )

    batchBase["transactions"] = approvals
    json.dump(batchBase, open("liquidator-approvals.json", "w"))
