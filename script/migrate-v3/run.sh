#!/bin/bash
source .env

python script/migrate-v3/fetchAccounts.py --block_number 18587325

forge script --rpc-url $MAINNET_RPC_URL -v script/migrate-v3/MigrateV3.s.sol