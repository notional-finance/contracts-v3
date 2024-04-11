# flake8: noqa
import json
import math
from brownie import NoteERC20, Router, network, interface
from brownie.network import Chain
from brownie.network.contract import Contract
from tests.constants import SECONDS_IN_YEAR
from tests.helpers import get_balance_action, get_balance_trade_action

chain = Chain()

def get_router_args(router):
    return [
        router.GOVERNANCE(),
        router.VIEWS(),
        router.INITIALIZE_MARKET(),
        router.NTOKEN_ACTIONS(),
        router.BATCH_ACTION(),
        router.ACCOUNT_ACTION(),
        router.ERC1155(),
        router.LIQUIDATE_CURRENCY(),
        router.LIQUIDATE_FCASH(),
        router.TREASURY(),
        router.CALCULATION_VIEWS(),
        router.VAULT_ACCOUNT_ACTION(),
        router.VAULT_ACTION(),
        router.VAULT_LIQUIDATION_ACTION(),
        router.VAULT_ACCOUNT_HEALTH(),
    ]

def get_multicall():
    multicall_abi = json.load(open("abi/Multicall3.json"))
    return Contract.from_abi(
        "Multicall", "0xcA11bde05977b3631167028862bE2a173976CA11", multicall_abi
    )

def get_ntoken_spot_value(notional, currencyId):
    address = notional.nTokenAddress(currencyId)
    (_, fCashAssets) = notional.getNTokenPortfolio(address)
    markets = notional.getActiveMarkets(currencyId)
    ntoken = notional.getNTokenAccount(address)
    totalPCash = ntoken['cashBalance']
    totalUnderlying = 0
    oracleValue = notional.nTokenPresentValueUnderlyingDenominated(currencyId)

    for i in range(0, len(fCashAssets)):
        netFCash = fCashAssets[i][3] + markets[i][2]
        timeToMaturity = markets[i][1] - chain.time()
        discountFactor = math.exp(-(markets[i][5] * timeToMaturity) / (1e9 * SECONDS_IN_YEAR))
        totalUnderlying += netFCash * discountFactor
        totalPCash += markets[i][3]

    totalUnderlying += notional.convertCashBalanceToExternal(currencyId, totalPCash, True) * 1e8 / 1e6
    return (totalUnderlying / ntoken['totalSupply'], oracleValue / ntoken['totalSupply'], totalUnderlying, oracleValue, ntoken['totalSupply'])

def mint_ntokens(notional, currencyId, account, amount):
    # >>> whale = '0xb38e8c17e38363af6ebdcb3dae12e0243582891d'
    # >>> usdt = Contract.from_explorer('0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9')
    notional.batchBalanceAction(account, [
        get_balance_action(currencyId, "DepositUnderlyingAndMintNToken", depositActionAmount=amount)
    ], {"from": account})

def get_addresses():
    networkName = network.show_active()
    if networkName == "mainnet-fork" or networkName == "mainnet-current":
        networkName = "mainnet"
    if networkName == "arbitrum-fork" or networkName == "arbitrum-current":
        networkName = "arbitrum-one"
    if networkName == "goerli-fork":
        networkName = "goerli"
    output_file = "v3.{}.json".format(networkName)
    addresses = None
    with open(output_file, "r") as f:
        addresses = json.load(f)

    notional = Contract.from_abi("Notional", addresses["notional"], abi=interface.NotionalProxy.abi)
    note = NoteERC20.at(addresses["note"])
    router = Contract.from_abi("Router", addresses["notional"], abi=Router.abi)
    multicall = get_multicall()

    return (addresses, notional, note, router, networkName, multicall)

def main():
    (addresses, notional, note, router, networkName, multicall) = get_addresses()
