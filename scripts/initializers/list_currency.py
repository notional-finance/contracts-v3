from brownie import ZERO_ADDRESS, Contract, accounts, interface
from scripts.arbitrum.arb_deploy import _deploy_chainlink_oracle, _deploy_pcash_oracle, _to_interest_rate_curve
from scripts.common import TokenType
from scripts.inspect import get_addresses
import json
from tests.helpers import get_balance_action

WHALES = {
    'cbETH': "0xba12222222228d8ba445958a75a0704d566bf2c8",
    'GMX': "0x908c4d94d34924765f1edc22a1dd098397c59dd4",
    'ARB': "0xf3fc178157fb3c87548baa86f9d24ba38e649b58",
    'RDNT': "0x9d9e4A95765154A575555039E9E2a321256B5704"
}

LIQUIDATOR = '0xaCe757160cedD8b735f3dc19870A52F611F04a2e'

def donate_initial(symbol, notional, fundingAccount, config):
    token = config[symbol]
    if symbol == 'ETH':
        fundingAccount.transfer(notional, 0.01e18)
    else:
        erc20 = Contract.from_abi("token", token['address'], interface.IERC20.abi)
        # whale = WHALES[symbol]
        # erc20.transfer(fundingAccount, 10 * 10 ** erc20.decimals(), {"from": whale})
        # Donate the initial balance
        erc20.transfer(notional, 0.05 * 10 ** erc20.decimals(), {"from": fundingAccount})

def list_currency(notional, symbol, tradingModule, config):
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
    callData.append(txn.input)

    txn = notional.setMaxUnderlyingSupply(currencyId, token['maxUnderlyingSupply'], {"from": notional.owner()})
    callData.append(txn.input)

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
        callData.append(txn.input)

        txn = notional.updateInterestRateCurve(
            currencyId,
            [1, 2],
            [_to_interest_rate_curve(c) for c in token['fCashCurves']],
            {"from": notional.owner()}
        )
        callData.append(txn.input)

        txn = notional.updateDepositParameters(currencyId, token['depositShare'], token['leverageThreshold'], {"from": notional.owner()})
        callData.append(txn.input)

        txn = notional.updateInitializationParameters(currencyId, [0, 0], token['proportion'], {"from": notional.owner()})
        callData.append(txn.input)

        txn = notional.updateTokenCollateralParameters(
            currencyId,
            token["residualPurchaseIncentive"],
            token["pvHaircutPercentage"],
            token["residualPurchaseTimeBufferHours"],
            token["cashWithholdingBuffer10BPS"],
            token["liquidationHaircutPercentage"],
            {"from": notional.owner()}
        )
        callData.append(txn.input)
    
    # Set trading module approvals for the liquidator
    txn = tradingModule.setTokenPermissions(
        LIQUIDATOR,
        token['address'],
        (True, 8, 15), # allow sell, 8 is 0x, 15 is all trade types
        {"from": notional.owner()}
    )

    return {'notional': callData, 'tradingModule': txn.input}

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

def main(ListedTokens, listTokens):
    fundingAccount = accounts.at("0x7d7935EDd4b6cDB5f34B0E1cCEAF85a3C4A11254", force=True)
    (addresses, notional, note, router, networkName) = get_addresses()
    deployer = accounts.at("0x8F5ea3CDe898B208280c0e93F3aDaaf1F5c35a7e", force=True)
    # deployer = accounts.load(networkName.upper() + "_DEPLOYER")
    print("DEPLOYER ADDRESS", deployer.address)
    tradingModule = Contract.from_abi("trading", addresses["tradingModule"], interface.ITradingModule.abi)

    for t in listTokens:
        donate_initial(t, notional, fundingAccount)
        if ListedTokens[t]["pCashOracle"] == "":
            # These contracts are verified automatically on Arbiscan
            print("DEPLOYING PCASH ORACLE FOR: ", t)
            pCash = _deploy_pcash_oracle(t, notional, deployer)
            ListedTokens[t]["pCashOracle"] = pCash.address
        if "baseOracle" in ListedTokens[t] and ListedTokens[t]["ethOracle"] == "":
            # These contracts are verified automatically on Arbiscan
            print("DEPLOYING ETH ORACLE FOR: ", t)
            ethOracle = _deploy_chainlink_oracle(t, deployer)
            ListedTokens[t]["ethOracle"] = ethOracle.address

    batchBase = {
        "version": "1.0",
        "chainId": "42161",
        "createdAt": 1692567274357,
        "meta": {
            "name": "Transactions Batch",
            "description": "",
            "txBuilderVersion": "1.16.1"
        },
        "transactions": []
    }

    for t in listTokens:
        batchBase['transactions'] = []
        transactions = list_currency(notional, t, tradingModule, ListedTokens)
        for data in transactions['notional']:
            batchBase['transactions'].append({
                "to": notional.address,
                "value": "0",
                "data": data,
                "contractMethod": { "inputs": [], "name": "fallback", "payable": True },
                "contractInputsValues": None
            })

        batchBase['transactions'].append({
            "to": tradingModule.address,
            "value": "0",
            "data": transactions['tradingModule'],
            "contractMethod": { "inputs": [], "name": "fallback", "payable": True },
            "contractInputsValues": None
        })
        
        json.dump(batchBase, open("batch-{}.json".format(t), 'w'))

        token = ListedTokens[t]
        if "maxMarketIndex" in token:
            # Mint nTokens and Init Markets
            erc20 = Contract.from_abi("token", token['address'], interface.IERC20.abi)
            erc20.approve(notional, 2 ** 255, {"from": fundingAccount})

            notional.batchBalanceAction(fundingAccount, [
                get_balance_action(
                    9, "DepositUnderlyingAndMintNToken", depositActionAmount=0.05e18
                )
            ], {'from': fundingAccount})
            notional.initializeMarkets(9, True, {'from': fundingAccount})
