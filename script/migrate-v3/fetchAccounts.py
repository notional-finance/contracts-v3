import os
import requests
import argparse
import json

def get_accounts_page(block_number, skip=0):
    endpoint = "https://api.thegraph.com/subgraphs/name/notional-finance/mainnet-v2"

    # Your GraphQL query
    query = """
    {
      accounts(first: 1000, block: { number: %s }, skip: %s) { 
        id
        portfolio {
          currency {id}
          maturity
          notional
        }
      }
    }
    """ % (block_number, skip)

    response = requests.post(endpoint, json={"query": query})
    return response.json()["data"]["accounts"]

def paginate_accounts(block_number):
    all_accounts = []
    skip = 0

    while True:
        result = get_accounts_page(block_number, skip)

        if not result:
            break

        accounts = result
        all_accounts.extend(accounts)

        # Increment the skip value for the next page
        skip += len(accounts)

    return all_accounts

def process_accounts(all_accounts):
    # Group accounts by currency.id and maturity, summing up notional values
    totalFCashDebt = {}
    account_ids = []

    for account in all_accounts:
        for portfolio_entry in account["portfolio"]:
            currency_id = portfolio_entry["currency"]["id"]
            maturity = portfolio_entry["maturity"]
            notional = int(portfolio_entry["notional"])

            # Only sum negative notional values
            if notional < 0:
                key = (currency_id, maturity)
                if key not in totalFCashDebt:
                    totalFCashDebt[key] = {"notional_sum": 0}

                totalFCashDebt[key]["notional_sum"] += notional
                account_ids.append(account["id"])

        account_ids.append(account["id"])

    # Get the script directory
    script_dir = os.path.dirname(os.path.realpath(__file__))

    # Write account IDs to a JSON file in the script directory
    with open(os.path.join(script_dir, "accounts.json"), "w") as file:
        json.dump({"accounts": account_ids}, file)

    return totalFCashDebt

def write_total_fcash_debt(total_debt):
    # Get the script directory
    script_dir = os.path.dirname(os.path.realpath(__file__))

    # Write sorted output to a separate JSON file in the script directory
    with open(os.path.join(script_dir, "totalDebt.json"), "w") as file:
        formatted_output = {}

        for key, value in total_debt.items():
            currency_id = key[0]
            maturity = int(key[1])
            notional_sum = value["notional_sum"]

            if currency_id not in formatted_output:
                formatted_output[currency_id] = []

            formatted_output[currency_id].append({"maturity": maturity, "totalFCashDebt": -notional_sum})

        sorted_output = [
            v
            for (_, v) in sorted(formatted_output.items(), key=lambda x: x[0])
        ]

        json.dump({'debts': sorted_output}, file, indent=2)

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Paginate through GraphQL query for accounts.")
    parser.add_argument("--block_number", type=int, required=True, help="Block number for the query")
    args = parser.parse_args()

    all_accounts = paginate_accounts(args.block_number)
    total_debt = process_accounts(all_accounts)
    write_total_fcash_debt(total_debt)