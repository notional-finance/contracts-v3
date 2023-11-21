#!/bin/bash
source .env

export FORK_BLOCK=18587325

python script/migrate-v3/fetchAccounts.py --block_number $FORK_BLOCK

anvil --fork-url $MAINNET_RPC_URL --fork-block-number $FORK_BLOCK --silent &

ANVIL_PID=$!

sleep 2

forge script --rpc-url http://localhost:8545 -v script/migrate-v3/MigrateV3.s.sol

source venv/bin/activate

brownie run scripts/example.py --network mainnet-migration --interactive

kill $ANVIL_PID