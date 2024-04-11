import json
from scripts.inspect import get_addresses
from brownie import Contract, interface

# WBTC / USD
oracles = [
    # crvUSD
    ["0xf939E0A03FB07F59A73314E73794Be0E57ac1b4E", "0xEEf0C605546958c1f899b6fB336C20671f9cD49F"],
    # pyUSD
    ["0x6c3ea9036406852006290770BEdFcAbA0e23A0e8", "0x8f1dF6D7F2db73eECE86a18b4381F4707b918FB1"],
    # GHO
    ["0x40D16FC0246aD3160Ccc09B8D0D3A2cD28aE6C2f", "0x3f12643D3f6f874d39C2a4c9f2Cd6f2DbAC877FC"],
    # weETH
    ["0xCd5fE23C85820F7B72D0926FC9b05b43E359b7ee", "0xdDb6F90fFb4d3257dd666b69178e5B3c5Bf41136"],
    # osETH
    ["0xf1C9acDc66974dFB6dEcB12aA385b9cD01190E38", "0x3d3d7d124B0B80674730e0D31004790559209DEb"],
    # rETH
    ["0xae78736Cd615f374D3085123A210448E74Fc6393", "0xA7D273951861CF07Df8B0A1C3c934FD41bA9E8Eb"],
]

def main():
    (addresses, notional, *_) = get_addresses()
    tradingModule = Contract.from_abi(
        "trading", addresses["tradingModule"], interface.ITradingModule.abi
    )
    batchBase = {
        "version": "1.0",
        "chainId": "1",
        "createdAt": 1692567274357,
        "meta": {"name": "Transactions Batch", "description": "", "txBuilderVersion": "1.16.1"},
        "transactions": [],
    }

    txns = []
    for (token, oracle) in oracles:
        txns.append({
            "to": tradingModule.address,
            "value": "0",
            "data": tradingModule.setPriceOracle.encode_input(token, oracle),
            "contractMethod": {"inputs": [], "name": "fallback", "payable": True},
            "contractInputsValues": None,
        })

    batchBase['transactions'] = txns
    json.dump(batchBase, open("list-oracles.json", "w"))