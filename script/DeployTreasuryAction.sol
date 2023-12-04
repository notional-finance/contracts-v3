// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.11;

import "forge-std/Script.sol";

import {NotionalProxy} from "../interfaces/notional/NotionalProxy.sol";
import {IRouter} from "../interfaces/notional/IRouter.sol";

interface ITreasuryAction {
    function COMPTROLLER() external view returns (address);
}

contract DeployTreasuryAction is Script {
    function getDeployedContracts(address notional) private view returns (IRouter.DeployedContracts memory c) {
        IRouter r = IRouter(payable(notional));
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

        IRouter.DeployedContracts memory c = getDeployedContracts(address(NOTIONAL));

        c.treasury = deployCode(
            "TreasuryAction.sol:TreasuryAction", abi.encode(ITreasuryAction(c.treasury).COMPTROLLER(), REBALANCE_BOT)
        );

        IRouter r = IRouter(deployCode("Router.sol:Router", abi.encode(c)));

        NOTIONAL.upgradeTo(address(r));

        vm.stopBroadcast();
    }
}
