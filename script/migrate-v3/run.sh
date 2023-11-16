#!/bin/bash
source .env

forge script --rpc-url $MAINNET_RPC_URL -v script/migrate-v3/MigrateV3.s.sol