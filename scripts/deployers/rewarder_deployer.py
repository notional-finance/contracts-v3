import json
from itertools import chain

from brownie import SecondaryRewarder, accounts, MockERC20
from scripts.inspect import get_addresses
from tests.helpers import get_balance_action
from brownie.network import Chain

chain_ = Chain()

END_TIME = 1724457600 # Aug 24
ARB = '0x912CE59144191C1204E64559FE8253a0e49E6548'
GHO = '0x40D16FC0246aD3160Ccc09B8D0D3A2cD28aE6C2f'

ARB_REWARDERS = {
    "ETH": "0x3987F211d4BA25B6FF163B56051651bF6c6c5e54",
    "DAI": "0xE5b58DE62b71477aE4e10074fee48232DD7A2350",
    "USDC": "0xFc24ACF5BD2aFEe3efBd589F87B6610C9D162645",
    "WBTC": "0x8BC5600582c6c17194e4478C311d3133cf9361D2",
    "wstETH": "0xd2Da21d240F093A38A143426D3cd62326FC496cc",
    "FRAX": "0xA8cA4FA84933106a92D4fec68C8B5A057703e862",
    "rETH": "0xda99cd202bCac9f9c945fF2954e08EAec63B067d",
    "USDT": "0xe670942CE88d0ac8E655d30E5EF0229e969de26C",
    "cbETH": "0x9Bfbd9DF9E5f0bA9B43843bf89B590e41Ac01174"
}

ETH_REWARDERS = {
    "GHO": "0xbf35529d9333feEe50c17Aa0A39eeABea2b3ABB2",
}

batchBase = {
    "version": "1.0",
    "chainId": "1",
    "createdAt": 1692567274357,
    "meta": {
        "name": "Transactions Batch",
        "description": "",
        "txBuilderVersion": "1.16.1"
    },
    "transactions": []
}

DRY_RUN = True

def transfer_and_set(symbol, currencyId, transferAmount, emissionRate, notional):
    token = MockERC20.at(GHO)
    rewarder = SecondaryRewarder.at(ETH_REWARDERS[symbol])
    tx = []
    
    tx.append({
        "to": token.address,
        "value": "0",
        "data": token.transfer.encode_input(ETH_REWARDERS[symbol], transferAmount),
        "contractMethod": { "inputs": [], "name": "fallback", "payable": True },
        "contractInputsValues": None
    })

    tx.append({
        "to": rewarder.address,
        "value": "0",
        "data": rewarder.setIncentiveEmissionRate.encode_input(emissionRate, END_TIME),
        "contractMethod": { "inputs": [], "name": "fallback", "payable": True },
        "contractInputsValues": None
    })

    # if symbol != 'USDT':
    #     tx.append({
    #         "to": notional.address,
    #         "value": "0",
    #         "data": notional.setSecondaryIncentiveRewarder.encode_input(currencyId, rewarder),
    #         "contractMethod": { "inputs": [], "name": "fallback", "payable": True },
    #         "contractInputsValues": None
    #     })

    # Transfer
    if DRY_RUN:
        token.transfer(ETH_REWARDERS[symbol], transferAmount, {"from": notional.owner()})
        rewarder.setIncentiveEmissionRate(emissionRate, END_TIME, {"from": notional.owner()})
        notional.setSecondaryIncentiveRewarder(currencyId, rewarder, {"from": notional.owner()})

    return tx


def main():
    (_, notional, *_) = get_addresses()
    txns = []
    # deployer = accounts.load("MAINNET_DEPLOYER")
    # deployer = accounts[0]

    # eth = SecondaryRewarder.deploy(
    #     notional.address, 11, GHO, 0, END_TIME, {"from": deployer}
    # )
    # assert MockERC20.at(eth.NTOKEN_ADDRESS()).symbol() == 'nGHO'
    # assert eth.emissionRatePerYear() == 0

    txns.append(transfer_and_set('GHO', 11, 15_000e18, 60_000e8, notional))

    GHO_WHALE = '0x1a88Df1cFe15Af22B3c4c783D4e6F7F9e0C1885d'
    token = MockERC20.at(GHO)
    token.transfer(accounts[1], 900e18, {"from": GHO_WHALE})
    token.approve(notional.address, 900e18, {"from": accounts[1]})
    notional.batchBalanceAction(accounts[1], [
        get_balance_action(11, depositActionType="DepositUnderlyingAndMintNToken", depositActionAmount=900e18)
    ], {"from": accounts[1]})
    chain_.mine(timestamp=END_TIME)
    ghoBalanceBefore = token.balanceOf(accounts[1])
    notional.nTokenClaimIncentives({"from": accounts[1]})
    ghoBalanceAfter = token.balanceOf(accounts[1])

    flattened_list = list(chain.from_iterable(map(lambda x: x, txns)))

    batchBase['transactions'] = flattened_list

    json.dump(batchBase, open("rewarders.json", "w"))