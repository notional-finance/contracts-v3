#!/bin/python
from brownie import Contract, accounts, interface

accountList = [
  ["0x424da3eFC0dC677be66aFE1967Fb631fAbb86799", -33241165234, 1],
  ["0x424Fbdb0551e62091dc3E4E26540b665Fd942840", -500950, 1],
  ["0x624d217F1106ba653d1BD402261A7e8C3f2B45BD", -2572916849, 1],
  ["0x70C9Ea3Aa116665010d2C5FB16808dD82FE58ff0", -1657500, 1],
  ["0x72D493Cad445646f60E7155F8a09A501fa539E10", -7104850, 1],
]

totals = {1: 35823345383, 2: 1137088794727186, 3: 33488909418977, 4: 557264232697}

def main():
    notional = Contract.from_abi(
        "Notional",
        "0xD8229B55bD73c61D840d339491219ec6Fa667B0a",
        abi=interface.NotionalProxy.abi
    )

    print(totals)

    funding = accounts.load("GOERLI_FUNDING")
    # Todo: need to upgrade to allow me to mint cETH

    for [acct, bal, id] in accountList:
        if id == 1:
            notional.depositAssetToken(acct, id, -bal, {"from": funding})