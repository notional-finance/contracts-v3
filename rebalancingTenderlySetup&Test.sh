#!/bin/bash

# Function to delete Tenderly virtual testnet
delete_tenderly_testnet() {
    read -p "Do you want to delete the Tenderly virtual testnet? (y/n): " DELETE_CONFIRMATION

    if [[ $DELETE_CONFIRMATION == "y" || $DELETE_CONFIRMATION == "Y" ]]; then
        echo "Deleting Tenderly virtual testnet..."

        # Delete the virtual testnet
        DELETE_RESPONSE=$(curl -s -X DELETE "https://api.tenderly.co/api/v1/account/$TENDERLY_ACCOUNT_SLUG/project/$TENDERLY_PROJECT_SLUG/vnets/$VNET_ID" \
            -H "X-Access-Key: $TENDERLY_ACCESS_KEY" \
            -H "Accept: application/json")

        echo "Tenderly virtual testnet deleted successfully."
    else
        echo "Tenderly virtual testnet deletion skipped."
    fi
}


# Trap to catch errors, explicit exits, and normal script completion
trap delete_tenderly_testnet EXIT SIGINT

# Check if TENDERLY_RPC_URL is set
if [ -n "$TENDERLY_RPC_URL" ]; then
    # If TENDERLY_RPC_URL is set, use it for ETH_RPC_URL
    export ETH_RPC_URL="$TENDERLY_RPC_URL"
else
    # If TENDERLY_RPC_URL is not set, create a new Tenderly virtual testnet
    echo "No TENDERLY_RPC_URL variable set, creating new Tenderly virtual testnet..."

    # Set Tenderly credentials
    TENDERLY_ACCESS_KEY=$(grep TENDERLY_ACCESS_KEY .env | cut -d '=' -f2)
    TENDERLY_ACCOUNT_SLUG="notional-finance"
    TENDERLY_PROJECT_SLUG="notionalv2"

    # Set virtual testnet configuration
    VNET_SLUG="rebalancing-test-net-$(date +%Y%m%d-%H%M%S)"
    NETWORK_ID="42161"  # Arbitrum One
    BLOCK_NUMBER="latest"
    CHAIN_ID="42161"  # Arbitrum One chain ID

    # Create virtual testnet
    VNET_RESPONSE=$(curl -s -X POST "https://api.tenderly.co/api/v1/account/$TENDERLY_ACCOUNT_SLUG/project/$TENDERLY_PROJECT_SLUG/vnets" \
      -H "X-Access-Key: $TENDERLY_ACCESS_KEY" \
      -H "Content-Type: application/json" \
      -d '{
      "slug": "'$VNET_SLUG'",
      "fork_config": {
        "network_id": '$NETWORK_ID'
      },
      "virtual_network_config": {
        "chain_config": {
          "chain_id": '$CHAIN_ID'
        }
      }
    }')

    export ETH_RPC_URL=$(echo $VNET_RESPONSE | jq -r '.rpcs[] | select(.name == "Admin RPC") | .url')
    PUBLIC_RPC_URL=$(echo $VNET_RESPONSE | jq -r '.rpcs[] | select(.name == "Public RPC") | .url')
    export VNET_ID=$(echo $VNET_RESPONSE | jq -r '.id')

    if [ -z "$ETH_RPC_URL" ] || [ "$ETH_RPC_URL" == "null" ]; then
        echo "Error: Failed to extract Admin RPC URL from response"
        exit 1
    fi
fi

echo "ETH_RPC_URL set to: $ETH_RPC_URL"
VERIFIER_URL=$PUBLIC_RPC_URL/verify/etherscan
export ETHERSCAN_API_KEY=$TENDERLY_ACCESS_KEY

# Generate a random address and private key using cast and fund it
echo "Generating a random address and funding it..."
PRIVATE_KEY=$(cast wallet new | grep "Private key:" | awk '{print $3}')
FUND_ADDRESS=$(cast wallet address $PRIVATE_KEY)
FUND_AMOUNT="0x56bc75e2d63100000"  # 100 ETH in hexadecimal wei

cast rpc tenderly_setBalance $FUND_ADDRESS $FUND_AMOUNT

# Parse contract parameters from v3.arbitrum-one.json file
NOTIONAL_PROXY=$(jq -r '.notional' v3.arbitrum-one.json)
UNDERLYING=$(jq -r '.underlying' v3.arbitrum-one.json)
AAVE_LENDING_POOL=$(jq -r '.aaveLendingPool' v3.arbitrum-one.json)
POOL_DATA_PROVIDER=$(jq -r '.aavePoolDataProvider' v3.arbitrum-one.json)

# Get the currency ID from environment variable
# Define an array of currency IDs
CURRENCY_IDS=(2 3)

for CURRENCY_ID in "${CURRENCY_IDS[@]}"; do
    echo "Processing Currency ID: $CURRENCY_ID"

    # Use foundry cast to call getPrimeCashHoldingsOracle
    HOLDINGS_ORACLE=$(cast call $NOTIONAL_PROXY "getPrimeCashHoldingsOracle(uint16)(address)" $CURRENCY_ID)

    # Validate that we got a valid address for the holdings oracle
    if [ "$HOLDINGS_ORACLE" == "0x0000000000000000000000000000000000000000" ]; then
        echo "Error: Invalid Holdings Oracle address returned"
        exit 1
    fi

    UNDERLYING=$(cast call $HOLDINGS_ORACLE "underlying()(address)")
    # Query LENDING_POOL for ReserveData and extract aTokenAddress
    RESERVE_DATA=$(cast call $AAVE_LENDING_POOL "getReserveData(address)((uint256,uint128,uint128,uint128,uint128,uint128,uint40,uint16,address,address,address,address,uint128,uint128,uint128))" $UNDERLYING)
    ATOKEN_ADDRESS=$(echo $RESERVE_DATA | awk -F',' '{print $9}')

    # Validate that we got a valid address for the aToken
    if [ "$ATOKEN_ADDRESS" == "0x0000000000000000000000000000000000000000" ]; then
        echo "Error: Invalid aToken address returned"
        exit 1
    fi

    # Deploy the contract
    NEW_ORACLE_ADDRESS=$(forge create \
        --etherscan-api-key $ETHERSCAN_API_KEY \
        --verifier-url $VERIFIER_URL \
        --private-key $PRIVATE_KEY \
        contracts/external/pCash/AaveV3HoldingsOracle.sol:AaveV3HoldingsOracle \
        --constructor-args $NOTIONAL_PROXY $UNDERLYING $AAVE_LENDING_POOL $ATOKEN_ADDRESS $POOL_DATA_PROVIDER \
        --json | jq -r '.deployedTo')

    if [ -z "$NEW_ORACLE_ADDRESS" ]; then
        echo "Error: Failed to deploy AaveV3HoldingsOracle. NEW_ORACLE_ADDRESS is empty."
        exit 1
    else
        echo "Deployed AaveV3HoldingsOracle to: $NEW_ORACLE_ADDRESS"
    fi

    OWNER=$(cast call $NOTIONAL_PROXY "owner()(address)")

    # Call updatePrimeCashHoldingsOracle on NOTIONAL contract to update the oracle
    echo "Updating Prime Cash Holdings Oracle for Currency ID $CURRENCY_ID"

    # Prepare the transaction data
    TX_DATA=$(cast calldata "updatePrimeCashHoldingsOracle(uint16,address)" $CURRENCY_ID $NEW_ORACLE_ADDRESS)

    RESPONSE=$(cast rpc eth_sendTransaction '{ "from": "'"$OWNER"'", "to": "'"$NOTIONAL_PROXY"'", "data": "'"$TX_DATA"'" }')

    # Verify the update by querying the new oracle address
    NEW_HOLDINGS_ORACLE=$(cast call $NOTIONAL_PROXY "getPrimeCashHoldingsOracle(uint16)(address)" $CURRENCY_ID)

    # Validate that the new oracle address matches the deployed address
    if [ "$NEW_HOLDINGS_ORACLE" != "$NEW_ORACLE_ADDRESS" ]; then
        echo "Error: New Holdings Oracle address does not match the deployed address for Currency ID $CURRENCY_ID"
    else
        echo "Holdings Oracle successfully updated to the new address for Currency ID $CURRENCY_ID"
    fi
done

# Deploy RebalanceHelper contract
echo "Deploying RebalanceHelper contract..."
REBALANCE_HELPER_ADDRESS=$(forge create \
    --etherscan-api-key $ETHERSCAN_API_KEY \
    --verifier-url $VERIFIER_URL \
    --private-key $PRIVATE_KEY \
    contracts/bots/RebalanceHelper.sol:RebalanceHelper \
    --constructor-args $NOTIONAL_PROXY \
    --json | jq -r '.deployedTo')

echo "Deployed RebalanceHelper to: $REBALANCE_HELPER_ADDRESS"


# Verify the deployment
DEPLOYED_NOTIONAL=$(cast call $REBALANCE_HELPER_ADDRESS "NOTIONAL()(address)")

if [ "$DEPLOYED_NOTIONAL" != "$NOTIONAL_PROXY" ]; then
    echo "Error: Deployed RebalanceHelper's NOTIONAL address does not match the expected address"
    exit 1
else
    echo "RebalanceHelper successfully deployed with correct NOTIONAL address"
fi

# Set rebalancing bot on Notional proxy to RebalanceHelper address
echo "Setting rebalancing bot on Notional proxy..."

# Encode the function call
TX_DATA=$(cast calldata "setRebalancingBot(address)" $REBALANCE_HELPER_ADDRESS)

# Send the transaction
cast rpc eth_sendTransaction '{ "from": "'"$OWNER"'", "to": "'"$NOTIONAL_PROXY"'", "data": "'"$TX_DATA"'" }'

echo "Rebalancing bot set successfully"

# Verify the update by querying the new rebalancing bot address
NEW_REBALANCING_BOT=$(cast call $NOTIONAL_PROXY "rebalancingBot()(address)")

echo "New Rebalancing Bot: $NEW_REBALANCING_BOT"

# Validate that the new rebalancing bot address matches the RebalanceHelper address
if [ "$NEW_REBALANCING_BOT" != "$REBALANCE_HELPER_ADDRESS" ]; then
    echo "Error: New Rebalancing Bot address does not match the RebalanceHelper address"
    exit 1
else
    echo "Rebalancing Bot successfully updated to the RebalanceHelper address"
fi

# Check if rebalance is needed by calling checkRebalance on RebalanceHelper
echo "Checking if rebalance is needed..."

# Call checkRebalance on RebalanceHelper using cast call
CURRENCY_IDS=$(cast call $REBALANCE_HELPER_ADDRESS "checkRebalance()(uint16[])")

if [ "$CURRENCY_IDS" == "[]" ]; then
    echo "No currencies need rebalancing at this time."
else
    echo "The following currency IDs need rebalancing: $CURRENCY_IDS"
fi


# Run rebalancing by calling checkAndRebalance on RebalanceHelper
echo "Running rebalancing..."

# Encode the function call for checkAndRebalance
CHECK_AND_REBALANCE_DATA=$(cast calldata "checkAndRebalance()")
RELAYER_ADDRESS=$(cast call $REBALANCE_HELPER_ADDRESS "RELAYER_ADDRESS()(address)")

# Call checkAndRebalance on RebalanceHelper
TX_HASH=$(cast rpc eth_sendTransaction '{ "from": "'"$RELAYER_ADDRESS"'", "to": "'"$REBALANCE_HELPER_ADDRESS"'", "data": "'"$CHECK_AND_REBALANCE_DATA"'" }')

echo "Rebalancing transaction sent. Transaction hash: $TX_HASH"

# Check if the transaction was successful
TX_RECEIPT=$(cast receipt "$TX_HASH")
TX_STATUS=$(echo "$TX_RECEIPT" | grep "status" | awk '{print $2}')

if [ "$TX_STATUS" == "0x1" ]; then
    echo "Rebalancing transaction was successful."
else
    echo "Error: Rebalancing transaction failed. Status: $TX_STATUS"
    exit 1
fi

# Check if rebalance is needed after the operation
echo "Checking if rebalance is still needed..."

# Call checkRebalance() on RebalanceHelper to get updated currency IDs
UPDATED_CURRENCY_IDS=$(cast call $REBALANCE_HELPER_ADDRESS "checkRebalance()(uint16[])")

if [ "$UPDATED_CURRENCY_IDS" == "[]" ]; then
    echo "No currencies need rebalancing after the operation. Rebalancing was successful."
else
    echo "Warning: The following currency IDs still need rebalancing: $UPDATED_CURRENCY_IDS"
fi
