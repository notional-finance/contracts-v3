import json
from brownie import ZERO_ADDRESS, Contract, accounts, interface
from brownie.network import Chain
from scripts.arbitrum.arb_deploy import _deploy_pcash_oracle, _to_interest_rate_curve
from scripts.common import TokenType
from scripts.deploy_v3 import get_network
from scripts.deployers.oracle_deployer import deploy_chainlink_oracle
from scripts.inspect import get_addresses
from tests.helpers import get_balance_action
from scripts.mainnet.eth_config import ListedTokens as ETH_ListedTokens
from scripts.arbitrum.arb_config import ListedTokens as ARB_ListedTokens
import time

chain = Chain()

WHALES = {
    'cbETH': "0xba12222222228d8ba445958a75a0704d566bf2c8",
    'GMX': "0x908c4d94d34924765f1edc22a1dd098397c59dd4",
    'ARB': "0xf3fc178157fb3c87548baa86f9d24ba38e649b58",
    'RDNT': "0x9d9e4A95765154A575555039E9E2a321256B5704",
    'GHO': '0x1a88Df1cFe15Af22B3c4c783D4e6F7F9e0C1885d'
}

def donate_initial(symbol, notional, config):
    token = config[symbol]
    fundingAccount = notional.owner()

    if symbol == 'ETH':
        txn = fundingAccount.transfer(notional, 0.01e18)
    else:
        erc20 = Contract.from_abi("token", token['address'], interface.IERC20.abi)
        whale = WHALES[symbol]
        erc20.transfer(fundingAccount, 100.05 * 10 ** erc20.decimals(), {"from": whale})
        # Donate the initial balance
        txn = erc20.transfer(notional, 0.05 * 10 ** erc20.decimals(), {"from": fundingAccount})

    return txn

def _list_currency(notional, symbol, tradingModule, config, liquidator):
    token = config[symbol]
    callData = []

    txn = notional.listCurrency(
        (
            token['address'],
            False,
            TokenType["UnderlyingToken"] if symbol != "ETH" else TokenType["Ether"],
            token['decimals'],
            0,
        ),
        (
            token['ethOracle'],
            18,
            False,
            token["buffer"],
            token["haircut"],
            token["liquidationDiscount"],
        ),
        _to_interest_rate_curve(token['primeCashCurve']),
        token['pCashOracle'],
        token["allowDebt"],
        token['primeRateOracleTimeWindow5Min'],
        token['name'],
        symbol,
        {"from": notional.owner()}
    )
    currencyId = token['currencyId']
    callData.append(txn)

    txn = notional.setMaxUnderlyingSupply(
        currencyId,
        token['maxUnderlyingSupply'],
        token['maxPrimeDebtUtilization'],
        {"from": notional.owner()}
    )
    callData.append(txn)

    # Inside here, we are listing fCash
    if "maxMarketIndex" in token:
        txn = notional.enableCashGroup(
            currencyId,
            (
                token["maxMarketIndex"],
                token["rateOracleTimeWindow"],
                token["maxDiscountFactor"],
                token["reserveFeeShare"],
                token["debtBuffer"],
                token["fCashHaircut"],
                token["minOracleRate"],
                token["liquidationfCashDiscount"],
                token["liquidationDebtBuffer"],
                token["maxOracleRate"]
            ),
            token['name'],
            symbol,
            {"from": notional.owner()}
        )
        callData.append(txn)

        txn = notional.updateInterestRateCurve(
            currencyId,
            [1, 2],
            [_to_interest_rate_curve(c) for c in token['fCashCurves']],
            {"from": notional.owner()}
        )
        callData.append(txn)

        txn = notional.updateDepositParameters(currencyId, token['depositShare'], token['leverageThreshold'], {"from": notional.owner()})
        callData.append(txn)

        txn = notional.updateInitializationParameters(currencyId, [0, 0], token['proportion'], {"from": notional.owner()})
        callData.append(txn)

        txn = notional.updateTokenCollateralParameters(
            currencyId,
            token["residualPurchaseIncentive"],
            token["pvHaircutPercentage"],
            token["residualPurchaseTimeBufferHours"],
            token["cashWithholdingBuffer10BPS"],
            token["liquidationHaircutPercentage"],
            token["maxMintDeviation5BPS"],
            {"from": notional.owner()}
        )
        callData.append(txn)
    
    # Set trading module approvals for the liquidator
    txn = tradingModule.setTokenPermissions(
        liquidator,
        token['address'],
        (True, 8, 15), # allow sell, 8 is 0x, 15 is all trade types
        {"from": "0x22341fB5D92D3d801144aA5A925F401A91418A05"}
    )
    callData.append(txn)

    return callData

def check_trading_module_oracle(symbol, config, isFork):
    (addresses, notional, _, _, _) = get_addresses()
    tradingModule = Contract.from_abi("trading", addresses["tradingModule"], interface.ITradingModule.abi)
    token = config[symbol]
    tokenAddress = token['address']
    (oracle, _) = tradingModule.priceOracles(tokenAddress)
    if oracle == ZERO_ADDRESS:
        print("No Trading Module Oracle Defined for ", symbol)
        if isFork:
            txn = tradingModule.setPriceOracle(
                tokenAddress,
                token['usdOracle'],
                {"from": notional.owner()}
            )
            return txn.input
        else:
            return tradingModule.setPriceOracle.encode_input(
                tokenAddress,
                token['usdOracle']
            )
    else:
        assert oracle == token['usdOracle']

def append_txn(batchBase, txn):
    batchBase['transactions'].append({
        "to": txn.receiver,
        "value": txn.value,
        "data": txn.input,
        "contractMethod": { "inputs": [], "name": "fallback", "payable": True },
        "contractInputsValues": None
    })


def list_currency(ListedTokens, listTokens):
    (addresses, notional, *_, tradingModule) = get_addresses()
    deployer = accounts.at("0x8F5ea3CDe898B208280c0e93F3aDaaf1F5c35a7e", force=True)
    # deployer = accounts.load(networkName.upper() + "_DEPLOYER")
    print("DEPLOYER ADDRESS", deployer.address)
    liquidator = addresses["liquidator"]

    batchBase = {
        "version": "1.0",
        "chainId": str(chain.id),
        "createdAt": str(int(time.time() * 1000)),
        "meta": {
            "name": "Transactions Batch",
            "description": "",
            "txBuilderVersion": "1.16.1"
        },
        "transactions": []
    }

    for t in listTokens:
        batchBase['transactions'] = []
        txn = donate_initial(t, notional, ListedTokens)
        append_txn(batchBase, txn)

        if ListedTokens[t]["pCashOracle"] == "":
            # These contracts are verified automatically on Arbiscan
            print("DEPLOYING PCASH ORACLE FOR: ", t)
            pCash = _deploy_pcash_oracle(t, notional, deployer, ListedTokens)
            ListedTokens[t]["pCashOracle"] = pCash.address
        if "baseOracle" in ListedTokens[t] and ListedTokens[t]["ethOracle"] == "":
            # These contracts are verified automatically on Arbiscan
            print("DEPLOYING ETH ORACLE FOR: ", t)
            ethOracle = deploy_chainlink_oracle(t, deployer, ListedTokens)
            ListedTokens[t]["ethOracle"] = ethOracle.address

        transactions = _list_currency(notional, t, tradingModule, ListedTokens, liquidator)
        for txn in transactions:
            append_txn(batchBase, txn)

        token = ListedTokens[t]
        if "maxMarketIndex" in token:
            # Mint nTokens and Init Markets
            erc20 = Contract.from_abi("token", token['address'], interface.IERC20.abi)
            currencyId = token['currencyId']
            precision = 10 ** erc20.decimals()

            # Minting nTokens and init markets is all done atomically
            txn = erc20.approve(notional, 2 ** 255, {"from": notional.owner()})
            append_txn(batchBase, txn)

            txn = notional.batchBalanceAction(notional.owner(), [
                get_balance_action(
                    currencyId, "DepositUnderlyingAndMintNToken", depositActionAmount=100 * precision
                )
            ], {'from': notional.owner()})
            append_txn(batchBase, txn)

            txn = notional.initializeMarkets(currencyId, True, {'from': notional.owner()})
            append_txn(batchBase, txn)

        json.dump(batchBase, open("batch-{}.json".format(t), 'w'), indent=2)

def main():
    (networkName, isFork) = get_network()
    if networkName == "arbitrum-one":
        list_currency(ARB_ListedTokens, [])
    elif networkName == "mainnet":
        list_currency(ETH_ListedTokens, ["GHO"])