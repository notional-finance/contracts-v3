// SPDX-License-Identifier: GPL-3.0-only
pragma solidity >=0.7.6;
pragma abicoder v2;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";

import {NotionalTreasury} from "../interfaces/notional/NotionalTreasury.sol";

enum Module {
    RESOLVER,
    TIME,
    PROXY,
    SINGLE_EXEC
}

struct ModuleData {
    Module[] modules;
    bytes[] args;
}

interface IAutomate {
    function createTask(address, bytes calldata, ModuleData calldata, address) external returns (bytes32 taskId);

    function cancelTask(bytes32 taskId) external;
}

interface IOpsProxyFactory {
    function getProxyOf(address account) external view returns (address, bool);
}

contract CreateRebalanceGelatoTask is Script {
    function run() external {
        string memory json = vm.readFile("v3.arbitrum-one.json");
        address NOTIONAL = address(vm.parseJsonAddress(json, ".notional"));
        IAutomate automate = IAutomate(address(vm.parseJsonAddress(json, ".gelatoAutomate")));
        IOpsProxyFactory OPS_PROXY_FACTORY =
            IOpsProxyFactory(address(vm.parseJsonAddress(json, ".gelatoOpsProxyFactory")));

        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        ModuleData memory moduleData = ModuleData({modules: new Module[](1), args: new bytes[](1)});

        moduleData.modules[0] = Module.RESOLVER;

        moduleData.args[0] = abi.encode(NOTIONAL, abi.encodeWithSelector(NotionalTreasury.checkRebalance.selector));

        bytes32 id = automate.createTask(
            NOTIONAL,
            abi.encode(NotionalTreasury.rebalance.selector),
            moduleData,
            address(0) // will use gelato  1balance for funding
        );

        address taskCreator = vm.addr(deployerPrivateKey);
        (address dedicatedMsgSender,) = IOpsProxyFactory(OPS_PROXY_FACTORY).getProxyOf(taskCreator);

        console.log("Task id: ", uint256(id));
        console.log("Gelato bot address: ", dedicatedMsgSender);

        vm.stopBroadcast();
    }
}