// SPDX-License-Identifier: GPL-3.0-only
pragma solidity >=0.7.6;
pragma abicoder v2;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";

import {RebalanceHelper, NotionalProxy} from "../contracts/bots/RebalanceHelper.sol";

// forge script script/DeployRebalanceHelper.sol --account MAINNET_V2_DEPLOYER  --verify --verifier-url "https://api.arbiscan.io/api" --etherscan-api-key "xx" --fork-url "xx" --chain 42161 --broadcast
contract DeployRebalanceHelper is Script {
    function run() external {
        string memory json = vm.readFile("v3.arbitrum-one.json");
        NotionalProxy NOTIONAL = NotionalProxy(vm.parseJsonAddress(json, ".notional"));

        vm.startBroadcast();
        RebalanceHelper rebalancingBot = new RebalanceHelper(NOTIONAL);
        console.log("RebalanceHelper deployed at", address(rebalancingBot));
        vm.stopBroadcast();
    }
}