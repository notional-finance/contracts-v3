#!/bin/bash
set -e

# Function to delete Tenderly virtual testnet
delete_tenderly_testnet() {
    if [ "$ALREADY_DELETED" = true ]; then
        exit 0
    fi
    # Check if VNET_ID is set
    if [ -z "$VNET_ID" ]; then
        exit 0
    fi
    read -p "Do you want to delete the Tenderly virtual testnet? (y/n): " DELETE_CONFIRMATION

    if [[ $DELETE_CONFIRMATION == "y" || $DELETE_CONFIRMATION == "Y" ]]; then
        echo "Deleting Tenderly virtual testnet..."

        # Delete the virtual testnet
        DELETE_RESPONSE=$(curl -s -X DELETE "https://api.tenderly.co/api/v1/account/$TENDERLY_ACCOUNT_SLUG/project/$TENDERLY_PROJECT_SLUG/vnets/$VNET_ID" \
            -H "X-Access-Key: $TENDERLY_ACCESS_KEY" \
            -H "Accept: application/json")

        echo "Tenderly virtual testnet deleted successfully."
        ALREADY_DELETED=true
    else
        echo "Tenderly virtual testnet deletion skipped."
    fi
    exit 0
}


# Trap to catch errors, explicit exits, and normal script completion
trap delete_tenderly_testnet EXIT SIGINT

# Set max deposit on holding oracle
set_max_deposit() {
    local oracle_address=$1
    local max_deposit=$2
    local set_max_deposit_data=$(cast calldata "setMaxAbsoluteDeposit(uint256)" $max_deposit)
    cast rpc eth_sendTransaction '{ "from": "'"$OWNER"'", "to": "'"$oracle_address"'", "data": "'"$set_max_deposit_data"'" }' > /dev/null

    echo "Max deposit amount updated to: $(cast call $oracle_address "maxDeposit()(uint256)")"
}

set_rebalancing_parameters() {
    local currency_id=$1
    let target_utilization=$2
    let external_withdraw_threshold=$3

    local holding_oracle=$(cast call $NOTIONAL_PROXY "getPrimeCashHoldingsOracle(uint16)(address)" $currency_id)
    local holdings=$(cast call $holding_oracle "holdings()(address[])"|tr -d '[]')
    local tx_data=$(cast calldata "setRebalancingTargets(uint16,(address,uint8,uint16)[])" $currency_id "[($holdings,$target_utilization,$external_withdraw_threshold)]")

    cast rpc eth_sendTransaction '{ "from": "'"$OWNER"'", "to": "'"$NOTIONAL_PROXY"'", "data": "'"$tx_data"'" }' > /dev/null
    # Set rebalancing cooldown to 10 minutes (600 seconds)
    local cooldown_time=600
    local tx_data=$(cast calldata "setRebalancingCooldown(uint16,uint40)" $currency_id $cooldown_time)
    cast rpc eth_sendTransaction '{ "from": "'"$OWNER"'", "to": "'"$NOTIONAL_PROXY"'", "data": "'"$tx_data"'" }' > /dev/null
}

create_tenderly_virtual_testnet() {
    VNET_SLUG="rebalancing-test-net-$(date +%Y%m%d-%H%M%S)"
    NETWORK_ID="42161"  # Arbitrum One
    BLOCK_NUMBER="latest"
    CHAIN_ID="52161"  # Arbitrum One chain ID

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

    export TENDERLY_RPC_URL=$(echo $VNET_RESPONSE | jq -r '.rpcs[] | select(.name == "Admin RPC") | .url')
    PUBLIC_RPC_URL=$(echo $VNET_RESPONSE | jq -r '.rpcs[] | select(.name == "Public RPC") | .url')
    export VNET_ID=$(echo $VNET_RESPONSE | jq -r '.id')

    if [ -z "$TENDERLY_RPC_URL" ] || [ "$TENDERLY_RPC_URL" == "null" ]; then
        echo "Error: Failed to extract Admin RPC URL from response"
        exit 1
    fi
    
}



TENDERLY_ACCOUNT_SLUG="notional-finance"
TENDERLY_PROJECT_SLUG="notionalv2"
TENDERLY_RPC_URL=$(grep ^TENDERLY_RPC_URL .env | cut -d '=' -f2)
TENDERLY_ACCESS_KEY=$(grep ^TENDERLY_ACCESS_KEY .env | cut -d '=' -f2)
# Parse contract parameters from v3.arbitrum-one.json file
NOTIONAL_PROXY=$(jq -r '.notional' v3.arbitrum-one.json)
AAVE_LENDING_POOL=$(jq -r '.aaveLendingPool' v3.arbitrum-one.json)
POOL_DATA_PROVIDER=$(jq -r '.aavePoolDataProvider' v3.arbitrum-one.json)
OWNER=$(cast call $NOTIONAL_PROXY "owner()(address)")

# Check if TENDERLY_RPC_URL is set
if [ -z "$TENDERLY_RPC_URL" ]; then
    # If TENDERLY_RPC_URL is not set, create a new Tenderly virtual testnet
    echo "No TENDERLY_RPC_URL variable set, creating new Tenderly virtual testnet..."

    create_tenderly_virtual_testnet

fi

export ETH_RPC_URL="$TENDERLY_RPC_URL"
echo "ETH_RPC_URL set to: $ETH_RPC_URL"

TENDERLY_VERIFIER_URL=$TENDERLY_RPC_URL/verify/etherscan
export ETHERSCAN_API_KEY=$TENDERLY_ACCESS_KEY

# Generate a random address and private key using cast and fund it
PRIVATE_KEY=$(cast wallet new | grep "Private key:" | awk '{print $3}')
FUND_ADDRESS=$(cast wallet address $PRIVATE_KEY)
# Fund the address with 100 ETH
cast rpc tenderly_setBalance $FUND_ADDRESS "0x56bc75e2d63100000" > /dev/null


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
        --private-key $PRIVATE_KEY \
        --legacy \
        contracts/external/pCash/AaveV3HoldingsOracle.sol:AaveV3HoldingsOracle \
        --constructor-args $NOTIONAL_PROXY $UNDERLYING $AAVE_LENDING_POOL $ATOKEN_ADDRESS $POOL_DATA_PROVIDER \
        --json | jq -r '.deployedTo')

    forge verify-contract $NEW_ORACLE_ADDRESS  \
        contracts/external/pCash/AaveV3HoldingsOracle.sol:AaveV3HoldingsOracle \
        --etherscan-api-key $TENDERLY_ACCESS_KEY \
        --verifier-url $TENDERLY_VERIFIER_URL \
        --watch > /dev/null 2>&1


    if [ -z "$NEW_ORACLE_ADDRESS" ]; then
        echo "Error: Failed to deploy AaveV3HoldingsOracle. NEW_ORACLE_ADDRESS is empty."
        exit 1
    else
        echo "Deployed AaveV3HoldingsOracle to: $NEW_ORACLE_ADDRESS"
    fi

    OWNER=$(cast call $NOTIONAL_PROXY "owner()(address)")

    set_max_deposit "$NEW_ORACLE_ADDRESS" "10000000000000000000000"  # 10,000 tokens with 18 decimals


    # Call updatePrimeCashHoldingsOracle on NOTIONAL contract to update the oracle
    # Prepare the transaction data
    TX_DATA=$(cast calldata "updatePrimeCashHoldingsOracle(uint16,address)" $CURRENCY_ID $NEW_ORACLE_ADDRESS)

    cast rpc eth_sendTransaction '{ "from": "'"$OWNER"'", "to": "'"$NOTIONAL_PROXY"'", "data": "'"$TX_DATA"'" }' > /dev/null

    # Verify the update by querying the new oracle address
    NEW_HOLDINGS_ORACLE=$(cast call $NOTIONAL_PROXY "getPrimeCashHoldingsOracle(uint16)(address)" $CURRENCY_ID)

    # Validate that the new oracle address matches the deployed address
    if [ "$NEW_HOLDINGS_ORACLE" != "$NEW_ORACLE_ADDRESS" ]; then
        echo "Error: New Holdings Oracle address does not match the deployed address for Currency ID $CURRENCY_ID"
        exit 1
    fi

    set_rebalancing_parameters "$CURRENCY_ID" 90 110
done

# Deploy RebalanceHelper contract
REBALANCE_HELPER_ADDRESS=$(forge create \
    --private-key $PRIVATE_KEY \
    contracts/bots/RebalanceHelper.sol:RebalanceHelper \
    --constructor-args $NOTIONAL_PROXY \
    --json | jq -r '.deployedTo')

echo "Deployed RebalanceHelper to: $REBALANCE_HELPER_ADDRESS"

forge verify-contract $REBALANCE_HELPER_ADDRESS  \
    contracts/bots/RebalanceHelper.sol:RebalanceHelper \
    --etherscan-api-key $TENDERLY_ACCESS_KEY \
    --verifier-url $TENDERLY_VERIFIER_URL \
    --watch > /dev/null 2>&1
 
# Verify the deployment
DEPLOYED_NOTIONAL=$(cast call $REBALANCE_HELPER_ADDRESS "NOTIONAL()(address)")

if [ "$DEPLOYED_NOTIONAL" != "$NOTIONAL_PROXY" ]; then
    echo "Error: Deployed RebalanceHelper's NOTIONAL address does not match the expected address"
    exit 1
else
    echo "RebalanceHelper successfully deployed with correct NOTIONAL address"
fi

# Set rebalancing bot on Notional proxy to RebalanceHelper address

# Encode the function call
TX_DATA=$(cast calldata "setRebalancingBot(address)" $REBALANCE_HELPER_ADDRESS)

# Send the transaction
cast rpc eth_sendTransaction '{ "from": "'"$OWNER"'", "to": "'"$NOTIONAL_PROXY"'", "data": "'"$TX_DATA"'" }' > /dev/null

RELAYER_ADDRESS=$(cast call $REBALANCE_HELPER_ADDRESS "RELAYER_ADDRESS()(address)")

check_rebalance_needed() {
    # Check if rebalance is needed by calling checkRebalance on RebalanceHelper
    echo "Checking if rebalance is needed..."

    # Call checkRebalance on RebalanceHelper using cast call
    CURRENCY_IDS=$(cast call $REBALANCE_HELPER_ADDRESS "checkRebalance()(uint16[])")

    if [ "$CURRENCY_IDS" == "[]" ]; then
        echo "No currencies need rebalancing at this time."
    else
        echo "The following currency IDs need rebalancing: $CURRENCY_IDS"
    fi
}

perform_rebalancing() {
    check_rebalance_needed
    # Present options to the user
    echo "Please choose an option:"
    echo "1. Rebalance all currencies"
    echo "2. Enter custom currency IDs to rebalance"
    echo "3. Fast forward time"
    echo "4. Change max deposit on holding oracle"
    echo "5. Exit"
    read -p "Enter your choice (1-3): " choice

    case $choice in
        1)
            echo "Rebalancing all available currencies..."

            CHECK_AND_REBALANCE_DATA=$(cast calldata "checkAndRebalance()")

            # Call checkAndRebalance on RebalanceHelper
            TX_HASH=$(cast rpc eth_sendTransaction '{ "from": "'"$RELAYER_ADDRESS"'", "to": "'"$REBALANCE_HELPER_ADDRESS"'", "data": "'"$CHECK_AND_REBALANCE_DATA"'" }')

            echo "Rebalancing transaction sent."

            perform_rebalancing
            ;;
        2)
            echo "Enter currency IDs separated by spaces (e.g., 1 2 3):"
            read -a custom_ids
            if [ ${#custom_ids[@]} -eq 0 ]; then
                echo "No currency IDs entered. Exiting."
                exit 0
            fi
            echo "Rebalancing custom currency IDs: ${custom_ids[*]}"
            # Check Notional proxy balance for each currency ID
            for id in "${custom_ids[@]}"; do
                HOLDINGS_ORACLE=$(cast call $NOTIONAL_PROXY "getPrimeCashHoldingsOracle(uint16)(address)" $id)
                TOKEN_ADDRESS=$(cast call $HOLDINGS_ORACLE "underlying()(address)")
                
                # Get the balance of the token for Notional proxy
                BALANCE=$(cast call $TOKEN_ADDRESS "balanceOf(address)(uint256)" $NOTIONAL_PROXY)
                
                echo "Currency ID $id (Token: $TOKEN_ADDRESS) balance: $BALANCE"
            done
            # Encode the function call for rebalanceCurrencyIds with custom currency IDs
            REBALANCE_ALL_DATA=$(cast calldata "rebalanceCurrencyIds(uint16[])" "[${custom_ids[*]}]")
            
            # Call rebalanceCurrencyIds on RebalanceHelper with custom currency IDs
            CUSTOM_TX_HASH=$(cast rpc eth_sendTransaction '{ "from": "'"$RELAYER_ADDRESS"'", "to": "'"$REBALANCE_HELPER_ADDRESS"'", "data": "'"$REBALANCE_ALL_DATA"'" }')
            
            echo "Custom rebalancing transaction sent"

            for id in "${custom_ids[@]}"; do
                HOLDINGS_ORACLE=$(cast call $NOTIONAL_PROXY "getPrimeCashHoldingsOracle(uint16)(address)" $id)
                TOKEN_ADDRESS=$(cast call $HOLDINGS_ORACLE "underlying()(address)")

                # Get the balance of the token for Notional proxy
                BALANCE=$(cast call $TOKEN_ADDRESS "balanceOf(address)(uint256)" $NOTIONAL_PROXY)
                
                echo "Currency ID $id (Token: $TOKEN_ADDRESS) balance: $BALANCE"
            done
            
            perform_rebalancing
            ;;
        3)
            echo "Current block timestamp: $(cast block latest -f timestamp)"
            echo "Enter the number of minutes to fast forward:"
            read minutes
            
            # Use cast to set the next block's timestamp
            SECONDS_HEX=$(printf "0x%x" $((minutes * 60)))
            cast rpc evm_increaseTime $SECONDS_HEX

            echo "Time has been fast-forwarded by $minutes minutes."
            echo "Current block timestamp: $(cast block latest -f timestamp)"
            perform_rebalancing
            ;;
        4)
            echo "Enter the currency ID:"
            read currency_id
            echo "Enter the max deposit amount"
            read max_deposit_amount

            HOLDINGS_ORACLE=$(cast call $NOTIONAL_PROXY "getPrimeCashHoldingsOracle(uint16)(address)" $currency_id)
            set_max_deposit $HOLDINGS_ORACLE $max_deposit_amount
            perform_rebalancing
            ;;
        5)
            echo "Exiting without rebalancing."
            exit 0
            ;;
        *)
            echo "Invalid choice."
            perform_rebalancing
            ;;
    esac
}



# Main execution
perform_rebalancing
