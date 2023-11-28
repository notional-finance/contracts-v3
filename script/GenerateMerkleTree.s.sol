// SPDX-License-Identifier: GPL-3.0-only
pragma solidity >=0.7.6;

import {Script} from "forge-std/Script.sol";
import {console2 as console} from "forge-std/console2.sol";
import {Merkle} from "murky/src/Merkle.sol";

contract GenerateMerkleTree is Script {
    function run() external {
        string memory json = vm.readFile("script/merkleConfig.json");
        address[] memory accounts = vm.parseJsonAddressArray(json, ".accounts");
        uint256[] memory nTokenBalances = vm.parseJsonUintArray(json, ".nTokenBalances");
        require(accounts.length == nTokenBalances.length, "Invalid data");
        uint256 length = accounts.length;

        // Initialize
        Merkle m = new Merkle();
        bytes32[] memory data = new bytes32[](length);
        for (uint256 i = 0; i < length; ++i) {
            data[i] = keccak256(abi.encodePacked(accounts[i], nTokenBalances[i]));
        }

        string memory finalJson = "finalJson";
        for (uint256 i = 0; i < length; ++i) {
            string memory proofAndBalance = vm.toString(i);
            vm.serializeBytes32(proofAndBalance, "proof", m.getProof(data, i));
            proofAndBalance = vm.serializeUint(proofAndBalance, "balance", nTokenBalances[i]);
            vm.serializeString(finalJson, vm.toString(accounts[i]), proofAndBalance);
        }
        finalJson = vm.serializeBytes32(finalJson, "root", m.getRoot(data));

        vm.writeJson(finalJson, "./script/merkleProofs.json");
        console.log("Merkle proof generate!");
    }
}