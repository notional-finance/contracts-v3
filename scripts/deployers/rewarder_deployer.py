import json
from itertools import chain

from brownie import SecondaryRewarder, accounts, MockERC20
from scripts.inspect import get_addresses

END_TIME = 1707177600 # Jan 23
ARB = '0x912CE59144191C1204E64559FE8253a0e49E6548'
REWARDERS = {
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

DRY_RUN = True

def transfer_and_set(symbol, currencyId, transferAmount, emissionRate, notional):
    arb = MockERC20.at(ARB)
    rewarder = SecondaryRewarder.at(REWARDERS[symbol])
    tx = []
    
    tx.append({
        "to": arb.address,
        "value": "0",
        "data": arb.transfer.encode_input(REWARDERS[symbol], transferAmount),
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
        arb.transfer(REWARDERS[symbol], transferAmount, {"from": notional.owner()})
        rewarder.setIncentiveEmissionRate(emissionRate, END_TIME, {"from": notional.owner()})
        # if symbol != 'USDT':
        #     notional.setSecondaryIncentiveRewarder(currencyId, rewarder, {"from": notional.owner()})

    return tx


def main():
    (_, notional, *_) = get_addresses()
    txns = []

    # eth = SecondaryRewarder.deploy(
    #     notional.address, 1, ARB, 0, END_TIME, {"from": deployer}
    # )
    # assert MockERC20.at(eth.NTOKEN_ADDRESS()).symbol() == 'nETH'
    # assert eth.emissionRatePerYear() == 0

    txns.append(transfer_and_set('ETH',    1, 10_560e18, 499_200e8, notional))
    txns.append(transfer_and_set('DAI',    2, 4_400e18,  208_000e8, notional))
    txns.append(transfer_and_set('USDC',   3, 10_560e18, 499_200e8, notional))
    txns.append(transfer_and_set('WBTC',   4,   880e18,   41_600e8, notional))
    txns.append(transfer_and_set('wstETH', 5, 4_400e18,  208_000e8, notional))
    txns.append(transfer_and_set('FRAX',   6, 4_400e18,  208_000e8, notional))
    txns.append(transfer_and_set('rETH',   7, 4_400e18,  208_000e8, notional))
    txns.append(transfer_and_set('USDT',   8, 4_400e18,  208_000e8, notional))
    # txns.append(transfer_and_set('cbETH', 9, 0e18, 0, notional))
    
    flattened_list = list(chain.from_iterable(map(lambda x: x, txns)))

    batchBase['transactions'] = flattened_list

    json.dump(batchBase, open("rewarders.json", "w"))