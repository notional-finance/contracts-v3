import json
import requests
from brownie import Contract
from scripts.gnosis_helper import append_txn, get_batch_base
from scripts.inspect import get_addresses


# Define the GraphQL query
query = """
query reserveBalanceAtBlock($block: Int){
  balances(where: {
    account_: {systemAccountType: FeeReserve }
  }, block: { number: $block } ) {
    token {
      currencyId
      symbol
      underlying {
        symbol
        precision
        tokenAddress
      }
    }
    current {
       currentBalance
    }
  }
}
"""

def get_block_for_timestamp(network, timestamp):
    url = f"https://coins.llama.fi/block/{network}/{timestamp}"
    # Make the GET request
    response = requests.get(url)

    # Check if the request was successful
    if response.status_code == 200:
        # Parse the response as JSON
        return response.json()['height']
    else:
        raise Exception(f"Failed to retrieve data: {response.status_code}")

def get_reserves_at_timestamp(network, timestamp):
    # Define the URL for the GraphQL endpoint
    url = f"https://api.studio.thegraph.com/query/36749/notional-v3-{network}/version/latest"

    variables = {
        "block": get_block_for_timestamp(network, timestamp)
    }

    payload = {
        "query": query,
        "variables": variables
    }

    # Send the request to the GraphQL endpoint
    response = requests.post(url, json=payload)

    if response.status_code == 200:
        # Parse the response as JSON
        return response.json()['data']['balances']
    else:
        raise Exception(f"Failed to retrieve data: {response.status_code}")

REINVESTMENT_RATE = 0.2
RESERVE_BALANCE_DATE = 1711868400
NETWORK = "arbitrum" # or "mainnet"

def main():
    (addresses, notional, *_, tradingModule) = get_addresses()
    balances = get_reserves_at_timestamp(NETWORK, RESERVE_BALANCE_DATE)
    sorted_balances = sorted(balances, key=lambda x: x['token']['currencyId'])
    TreasuryManagerABI = json.load(open("abi/TreasuryManager.json"))
    treasury = Contract.from_abi("treasuryManager", addresses['treasuryManager'], TreasuryManagerABI)
    batchBase = get_batch_base()

    all_ids = []
    for balance in sorted_balances:
        currency_id = balance['token']['currencyId']
        all_ids.append(currency_id)
        harvestAmount = int(balance['current']['currentBalance']) * REINVESTMENT_RATE
        reserveBuffer = notional.getReserveBalance(currency_id) - harvestAmount
        txn = notional.setReserveBuffer(currency_id, reserveBuffer, {"from": notional.owner()})
        append_txn(batchBase, txn)

    # notional.setTreasuryManager(treasury.address, {"from": notional.owner()})
    txn = treasury.harvestAssetsFromNotional(all_ids, {"from": treasury.manager()})
    harvested = txn.events['AssetsHarvested']['amounts']
    for (i, h) in enumerate(harvested):
        u = sorted_balances[i]['token']['underlying']
        print(f"Harvested {h / int(u['precision'])} {u['symbol']} from treasury")
        # if u['symbol'] != 'ETH':
        #   txn = tradingModule.setTokenPermissions(treasury.address, u['tokenAddress'], (True, 8, 15), {"from": notional.owner()})
        #   append_txn(batchBase, txn)

    json.dump(batchBase, open("treasury-manager.json", 'w'), indent=2)