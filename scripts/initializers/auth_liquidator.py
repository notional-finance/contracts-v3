import json
from brownie import interface, Contract
from scripts.mainnet.eth_config import ListedTokens

def main():
    tradingModule = Contract.from_abi(
        "Trading Module",
        "0x594734c7e06C3D483466ADBCe401C6Bd269746C8",
        interface.ITradingModule.abi
    )
    flashLiquidator = "0x7E9819C4fd31Efdd16Abb9e4C2b87F9991195493"
    batchBase = {
        "version": "1.0",
        "chainId": "1",
        "createdAt": 1692567274357,
        "meta": {
            "name": "Transactions Batch",
            "description": "",
            "txBuilderVersion": "1.16.1"
        },
        "transactions": [
            {
                "to": tradingModule.address,
                "value": "0",
                "data": tradingModule.setTokenPermissions.encode_input(
                    flashLiquidator,
                    l["address"],
                    (True, 8, 15)
                ),
                "contractMethod": { "inputs": [], "name": "fallback", "payable": True },
                "contractInputsValues": None
            }

            for (_, l) in ListedTokens.items()
        ] + [ {
                "to": tradingModule.address,
                "value": "0",
                "data": tradingModule.setTokenPermissions.encode_input(
                    flashLiquidator,
                    # WETH address
                    "0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2",
                    (True, 8, 15)
                ),
                "contractMethod": { "inputs": [], "name": "fallback", "payable": True },
                "contractInputsValues": None
        }]
    }

    json.dump(batchBase, open("batch-liquidator.json", 'w'))
