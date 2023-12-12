#!/bin/python
import json
from brownie import ZERO_ADDRESS, Contract, accounts, CompoundV2HoldingsOracle, EmptyProxy, UpgradeableBeacon, nTokenERC20Proxy, PrimeCashProxy, PrimeDebtProxy, interface, network, MigrationSettings, MigratePrimeCash
from brownie.network import Chain
from scripts.deployment import deployNotionalContracts

chain = Chain()

OWNER = "0xf862895976F693907f0AF8421Fe9264e559c2f6b"
DEPLOYER = "0x8B64fA5Fd129df9c755eB82dB1e16D6D0Bdf5Bc3"
BEACON_DEPLOYER = "0x0D251Bd6c14e02d34f68BFCB02c54cBa3D108122"

BeaconType = {
    "NTOKEN": 0,
    "PCASH": 1,
    "PDEBT": 2,
    "WFCASH": 3,
}

# This is on Goerli
LISTED_TOKENS = [
    {
        "symbol": "ETH",
        "address": "0x0000000000000000000000000000000000000000",
        "cToken": "0x97B44D189719Aa669f878cf0e558f86831D98E52",
        "cTokenRateAdapter": "0x97B44D189719Aa669f878cf0e558f86831D98E52"
    },
    {
        "symbol": "DAI",
        "address": "0x84e90bddff9a0e124f1ab7f4d1d33a7c748c1a16",
        "cToken": "0xeBE9243F7251922Bc0e5d33Dd329752158d10FaA",
        "cTokenRateAdapter": "0xeBE9243F7251922Bc0e5d33Dd329752158d10FaA"
    },
    {
        "symbol": "USDC",
        "address": "0x31dd61ac1b7a0bc88f7a58389c0660833a66c35c",
        "cToken": "0x3eFeA902182ce4B732A8ff8DAd106163fe7c023f",
        "cTokenRateAdapter": "0x3eFeA902182ce4B732A8ff8DAd106163fe7c023f"
    },
    {
        "symbol": "WBTC",
        "address": "0xfa8589db27c6369a6a4fdd857f783eddf857f2bc",
        "cToken": "0xEB3d46833144563553B2cB7057D1d89E291f5d68",
        "cTokenRateAdapter": "0xEB3d46833144563553B2cB7057D1d89E291f5d68"
    }
]

def deploy_beacons(deployer, emptyProxy, notional):
    assert deployer.address == BEACON_DEPLOYER
    assert deployer.nonce == 0

    nTokenBeacon = UpgradeableBeacon.deploy(emptyProxy, {"from": deployer})
    assert nTokenBeacon.address == "0xc4FD259b816d081C8bdd22D6bbd3495DB1573DB7"
    pCashBeacon = UpgradeableBeacon.deploy(emptyProxy, {"from": deployer})
    assert pCashBeacon.address == "0x1F681977aF5392d9Ca5572FB394BC4D12939A6A9"
    pDebtBeacon = UpgradeableBeacon.deploy(emptyProxy, {"from": deployer})
    assert pDebtBeacon.address == "0xDF08039c0af34E34660aC7c2705C0Da953247640"

    nTokenImpl = nTokenERC20Proxy.deploy(notional.address, {"from": deployer})
    pCashImpl = PrimeCashProxy.deploy(notional.address, {"from": deployer})
    pDebtImpl = PrimeDebtProxy.deploy(notional.address, {"from": deployer})

    nTokenBeacon.upgradeTo(nTokenImpl.address, {"from": deployer})
    pCashBeacon.upgradeTo(pCashImpl.address, {"from": deployer})
    pDebtBeacon.upgradeTo(pDebtImpl.address, {"from": deployer})

    nTokenBeacon.transferOwnership(notional.address, {"from": deployer})
    pCashBeacon.transferOwnership(notional.address, {"from": deployer})
    pDebtBeacon.transferOwnership(notional.address, {"from": deployer})

    # Nonce 103 and 104
    # https://etherscan.io/tx/0x947d60c781254637c5b9e774d8910a1187a31de606b3d3a515b6981662536fd2I
    # https://etherscan.io/tx/0x54c63544f562fd997d81fec94bc2189977b996e2ada8e3839e635aea513a6291
    # wfCashBeacon = UpgradeableBeacon.deploy(impl, {"from": deployer})

    return ( nTokenBeacon, pCashBeacon, pDebtBeacon )


def main():
    networkName = network.show_active()
    if networkName == "mainnet-fork" or networkName == "mainnet-current":
        networkName = "mainnet"
    if networkName == "goerli-fork":
        networkName = "goerli"
    output_file = "v2.{}.json".format(networkName)
    addresses = None
    with open(output_file, "r") as f:
        addresses = json.load(f)

    deployer = accounts.load("MAINNET_DEPLOYER")
    owner = OWNER # accounts.at(OWNER)
    beaconDeployer = accounts.load('BEACON_DEPLOYER')

    notional = Contract.from_abi("Notional", addresses["notional"], abi=interface.NotionalProxy.abi)

    impl = EmptyProxy.deploy(owner, {"from": deployer})
    (nTokenBeacon, pCashBeacon, pDebtBeacon) = deploy_beacons(beaconDeployer, impl, notional)
    (router, pauseRouter, contracts) = deployNotionalContracts(deployer, Comptroller=ZERO_ADDRESS)

    print(contracts)
    print("New Router", router.address)
    print("New Pause Router", pauseRouter)

    for token in LISTED_TOKENS:
        oracle = CompoundV2HoldingsOracle.deploy([
            notional.address,
            token['address'],
            token['cToken'],
            token['cTokenRateAdapter']
        ], {"from": deployer})
        print("Token Oracle {}: {}".format(token['symbol'], oracle.address))

    # Migration Settings
    settings = MigrationSettings.deploy(notional.address, owner, {"from": deployer})
    print("Settings", settings.address)

    # Migrate Prime Cash
    migrate = MigratePrimeCash.deploy(
        settings.address,
        router,
        pauseRouter,
        owner,
        {"from": deployer}
    )
    print("Migrate", migrate.address)

    # Settle all accounts
    allAccounts = json.load(open("script/migrate-v3/accounts.json", 'r'))
    multicall = Contract.from_abi("multicall", "0xcA11bde05977b3631167028862bE2a173976CA11", multicall_abi)
    multicall.aggregate3(
        [ 
            (notional.address, True, notional.settleAccount.encode_input(a))
            for a in allAccounts['accounts']
        ],
        {"from": deployer}
    )

    # TODO: Deposit cash into any accounts with negative cash
    # TODO: set settings
    # TODO: run migrate v3 script against fork RPC

multicall_abi = [
  {
    "inputs": [
      {
        "components": [
          {
            "internalType": "address",
            "name": "target",
            "type": "address"
          },
          {
            "internalType": "bytes",
            "name": "callData",
            "type": "bytes"
          }
        ],
        "internalType": "struct Multicall3.Call[]",
        "name": "calls",
        "type": "tuple[]"
      }
    ],
    "name": "aggregate",
    "outputs": [
      {
        "internalType": "uint256",
        "name": "blockNumber",
        "type": "uint256"
      },
      {
        "internalType": "bytes[]",
        "name": "returnData",
        "type": "bytes[]"
      }
    ],
    "stateMutability": "payable",
    "type": "function"
  },
  {
    "inputs": [
      {
        "components": [
          {
            "internalType": "address",
            "name": "target",
            "type": "address"
          },
          {
            "internalType": "bool",
            "name": "allowFailure",
            "type": "bool"
          },
          {
            "internalType": "bytes",
            "name": "callData",
            "type": "bytes"
          }
        ],
        "internalType": "struct Multicall3.Call3[]",
        "name": "calls",
        "type": "tuple[]"
      }
    ],
    "name": "aggregate3",
    "outputs": [
      {
        "components": [
          {
            "internalType": "bool",
            "name": "success",
            "type": "bool"
          },
          {
            "internalType": "bytes",
            "name": "returnData",
            "type": "bytes"
          }
        ],
        "internalType": "struct Multicall3.Result[]",
        "name": "returnData",
        "type": "tuple[]"
      }
    ],
    "stateMutability": "payable",
    "type": "function"
  },
  {
    "inputs": [
      {
        "components": [
          {
            "internalType": "address",
            "name": "target",
            "type": "address"
          },
          {
            "internalType": "bool",
            "name": "allowFailure",
            "type": "bool"
          },
          {
            "internalType": "uint256",
            "name": "value",
            "type": "uint256"
          },
          {
            "internalType": "bytes",
            "name": "callData",
            "type": "bytes"
          }
        ],
        "internalType": "struct Multicall3.Call3Value[]",
        "name": "calls",
        "type": "tuple[]"
      }
    ],
    "name": "aggregate3Value",
    "outputs": [
      {
        "components": [
          {
            "internalType": "bool",
            "name": "success",
            "type": "bool"
          },
          {
            "internalType": "bytes",
            "name": "returnData",
            "type": "bytes"
          }
        ],
        "internalType": "struct Multicall3.Result[]",
        "name": "returnData",
        "type": "tuple[]"
      }
    ],
    "stateMutability": "payable",
    "type": "function"
  },
  {
    "inputs": [
      {
        "components": [
          {
            "internalType": "address",
            "name": "target",
            "type": "address"
          },
          {
            "internalType": "bytes",
            "name": "callData",
            "type": "bytes"
          }
        ],
        "internalType": "struct Multicall3.Call[]",
        "name": "calls",
        "type": "tuple[]"
      }
    ],
    "name": "blockAndAggregate",
    "outputs": [
      {
        "internalType": "uint256",
        "name": "blockNumber",
        "type": "uint256"
      },
      {
        "internalType": "bytes32",
        "name": "blockHash",
        "type": "bytes32"
      },
      {
        "components": [
          {
            "internalType": "bool",
            "name": "success",
            "type": "bool"
          },
          {
            "internalType": "bytes",
            "name": "returnData",
            "type": "bytes"
          }
        ],
        "internalType": "struct Multicall3.Result[]",
        "name": "returnData",
        "type": "tuple[]"
      }
    ],
    "stateMutability": "payable",
    "type": "function"
  },
  {
    "inputs": [],
    "name": "getBasefee",
    "outputs": [
      {
        "internalType": "uint256",
        "name": "basefee",
        "type": "uint256"
      }
    ],
    "stateMutability": "view",
    "type": "function"
  },
  {
    "inputs": [
      {
        "internalType": "uint256",
        "name": "blockNumber",
        "type": "uint256"
      }
    ],
    "name": "getBlockHash",
    "outputs": [
      {
        "internalType": "bytes32",
        "name": "blockHash",
        "type": "bytes32"
      }
    ],
    "stateMutability": "view",
    "type": "function"
  },
  {
    "inputs": [],
    "name": "getBlockNumber",
    "outputs": [
      {
        "internalType": "uint256",
        "name": "blockNumber",
        "type": "uint256"
      }
    ],
    "stateMutability": "view",
    "type": "function"
  },
  {
    "inputs": [],
    "name": "getChainId",
    "outputs": [
      {
        "internalType": "uint256",
        "name": "chainid",
        "type": "uint256"
      }
    ],
    "stateMutability": "view",
    "type": "function"
  },
  {
    "inputs": [],
    "name": "getCurrentBlockCoinbase",
    "outputs": [
      {
        "internalType": "address",
        "name": "coinbase",
        "type": "address"
      }
    ],
    "stateMutability": "view",
    "type": "function"
  },
  {
    "inputs": [],
    "name": "getCurrentBlockDifficulty",
    "outputs": [
      {
        "internalType": "uint256",
        "name": "difficulty",
        "type": "uint256"
      }
    ],
    "stateMutability": "view",
    "type": "function"
  },
  {
    "inputs": [],
    "name": "getCurrentBlockGasLimit",
    "outputs": [
      {
        "internalType": "uint256",
        "name": "gaslimit",
        "type": "uint256"
      }
    ],
    "stateMutability": "view",
    "type": "function"
  },
  {
    "inputs": [],
    "name": "getCurrentBlockTimestamp",
    "outputs": [
      {
        "internalType": "uint256",
        "name": "timestamp",
        "type": "uint256"
      }
    ],
    "stateMutability": "view",
    "type": "function"
  },
  {
    "inputs": [
      {
        "internalType": "address",
        "name": "addr",
        "type": "address"
      }
    ],
    "name": "getEthBalance",
    "outputs": [
      {
        "internalType": "uint256",
        "name": "balance",
        "type": "uint256"
      }
    ],
    "stateMutability": "view",
    "type": "function"
  },
  {
    "inputs": [],
    "name": "getLastBlockHash",
    "outputs": [
      {
        "internalType": "bytes32",
        "name": "blockHash",
        "type": "bytes32"
      }
    ],
    "stateMutability": "view",
    "type": "function"
  },
  {
    "inputs": [
      {
        "internalType": "bool",
        "name": "requireSuccess",
        "type": "bool"
      },
      {
        "components": [
          {
            "internalType": "address",
            "name": "target",
            "type": "address"
          },
          {
            "internalType": "bytes",
            "name": "callData",
            "type": "bytes"
          }
        ],
        "internalType": "struct Multicall3.Call[]",
        "name": "calls",
        "type": "tuple[]"
      }
    ],
    "name": "tryAggregate",
    "outputs": [
      {
        "components": [
          {
            "internalType": "bool",
            "name": "success",
            "type": "bool"
          },
          {
            "internalType": "bytes",
            "name": "returnData",
            "type": "bytes"
          }
        ],
        "internalType": "struct Multicall3.Result[]",
        "name": "returnData",
        "type": "tuple[]"
      }
    ],
    "stateMutability": "payable",
    "type": "function"
  },
  {
    "inputs": [
      {
        "internalType": "bool",
        "name": "requireSuccess",
        "type": "bool"
      },
      {
        "components": [
          {
            "internalType": "address",
            "name": "target",
            "type": "address"
          },
          {
            "internalType": "bytes",
            "name": "callData",
            "type": "bytes"
          }
        ],
        "internalType": "struct Multicall3.Call[]",
        "name": "calls",
        "type": "tuple[]"
      }
    ],
    "name": "tryBlockAndAggregate",
    "outputs": [
      {
        "internalType": "uint256",
        "name": "blockNumber",
        "type": "uint256"
      },
      {
        "internalType": "bytes32",
        "name": "blockHash",
        "type": "bytes32"
      },
      {
        "components": [
          {
            "internalType": "bool",
            "name": "success",
            "type": "bool"
          },
          {
            "internalType": "bytes",
            "name": "returnData",
            "type": "bytes"
          }
        ],
        "internalType": "struct Multicall3.Result[]",
        "name": "returnData",
        "type": "tuple[]"
      }
    ],
    "stateMutability": "payable",
    "type": "function"
  }
]
