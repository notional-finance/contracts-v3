#!/bin/bash
source .env

export FORK_BLOCK=18587325

python script/migrate-v3/fetchAccounts.py --block_number $FORK_BLOCK

forge test --rpc-url $MAINNET_RPC_URL -vvv --mp script/migrate-v3/MigrateV3.s.sol