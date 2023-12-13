#!/bin/bash
source .env

export FORK_BLOCK=10206915

python script/migrate-v3/fetchAccounts.py --block_number $FORK_BLOCK

forge test --rpc-url $GOERLI_RPC_URL -vvv --mp script/migrate-v3/MigrateV3.s.sol