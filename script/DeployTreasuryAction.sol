// SPDX-License-Identifier: GPL-3.0-only
pragma solidity >=0.7.6;
pragma abicoder v2;

import {Script} from "forge-std/Script.sol";

import {TreasuryAction} from "../contracts/external/actions/TreasuryAction.sol";
import {Router} from "../contracts/external/Router.sol";
import {NotionalProxy} from "../interfaces/notional/NotionalProxy.sol";

contract DeployTreasuryAction is Script {
    function getDeployedContracts(address notional) private view returns (Router.DeployedContracts memory c) {
        Router r = Router(payable(notional));
        c.governance = r.GOVERNANCE();
        c.views = r.VIEWS();
        c.initializeMarket = r.INITIALIZE_MARKET();
        c.nTokenActions = r.NTOKEN_ACTIONS();
        c.batchAction = r.BATCH_ACTION();
        c.accountAction = r.ACCOUNT_ACTION();
        c.erc1155 = r.ERC1155();
        c.liquidateCurrency = r.LIQUIDATE_CURRENCY();
        c.liquidatefCash = r.LIQUIDATE_FCASH();
        c.treasury = r.TREASURY();
        c.calculationViews = r.CALCULATION_VIEWS();
        c.vaultAccountAction = r.VAULT_ACCOUNT_ACTION();
        c.vaultLiquidationAction = r.VAULT_LIQUIDATION_ACTION();
        c.vaultAccountHealth = r.VAULT_ACCOUNT_HEALTH();
    }

    function run() external {
        string memory json = vm.readFile("v3.arbitrum-one.json");
        NotionalProxy NOTIONAL = NotionalProxy(address(vm.parseJsonAddress(json, ".notional")));
        address REBALANCE_BOT = address(vm.parseJsonAddress(json, ".gelatoBot"));

        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        Router.DeployedContracts memory c = getDeployedContracts(address(NOTIONAL));

        c.treasury = address(new TreasuryAction());

        Router r = new Router(c);

        NOTIONAL.upgradeTo(address(r));

        NOTIONAL.setRebalancingBot(REBALANCE_BOT);

        vm.stopBroadcast();
    }
}