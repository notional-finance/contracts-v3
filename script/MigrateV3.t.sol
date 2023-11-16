// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;
pragma abicoder v2;

import "forge-std/Script.sol";
import { UpgradeRouter } from "./utils/UpgradeRouter.s.sol";
import { MigratePrimeCash } from "@notional-v3/external/patchfix/MigratePrimeCash.sol";
import { PauseRouter } from "@notional-v3/external/PauseRouter.sol";
import { Router } from "@notional-v3/external/Router.sol";
import { nProxy } from "../contracts/proxy/nProxy.sol";

contract MigrateToV3 is UpgradeRouter {
    address BEACON_DEPLOYER = 0x0D251Bd6c14e02d34f68BFCB02c54cBa3D108122;
    address DEPLOYER = 0x8B64fA5Fd129df9c755eB82dB1e16D6D0Bdf5Bc3;
    address MANAGER = 0x02479BFC7Dce53A02e26fE7baea45a0852CB0909;

//     UpgradeableBeacon nTokenBeacon;
//     UpgradeableBeacon pCashBeacon;
//     UpgradeableBeacon pDebtBeacon;

    modifier usingAccount(address account) {
        vm.startPrank(account);
        _;
        vm.stopPrank();
    }

//     function deployBeacons(EmptyProxy emptyImpl) internal usingAccount(BEACON_DEPLOYER) {
//         nTokenBeacon = new UpgradeableBeacon(emptyImpl);
//         require(address(nTokenBeacon) == address(Deployments.NTOKEN_BEACON));
//         pCashBeacon = new UpgradeableBeacon(emptyImpl);
//         require(address(pCashBeacon) == address(Deployments.PCASH_BEACON));
//         pDebtBeacon = new UpgradeableBeacon(emptyImpl);
//         require(address(pDebtBeacon) == address(Deployments.PDEBT_BEACON));
//     }

    function deployMigratePrimeCash() internal usingAccount(DEPLOYER) returns (
        MigratePrimeCash m,
        PauseRouter pauseRouter,
        Router finalRouter
    ) {
        // NOTE: these may need to be deployed manually via forge create
        ExternalLib[] memory libs = new ExternalLib[](NUM_LIBS);
        libs[0] = ExternalLib.FreeCollateral;
        libs[1] = ExternalLib.SettleAssets;
        libs[2] = ExternalLib.MigrateIncentives;
        libs[3] = ExternalLib.TradingAction;
        libs[4] = ExternalLib.nTokenMint;
        libs[5] = ExternalLib.nTokenRedeem;

        ActionContract[] memory actions = new ActionContract[](15);
        actions[0] = ActionContract.Governance;
        actions[1] = ActionContract.Views;
        actions[2] = ActionContract.InitializeMarket;
        actions[3] = ActionContract.nTokenAction;
        actions[4] = ActionContract.BatchAction;
        actions[5] = ActionContract.AccountAction;
        actions[6] = ActionContract.ERC1155;
        actions[7] = ActionContract.LiquidateCurrency;
        actions[8] = ActionContract.LiquidatefCash;
        actions[9] = ActionContract.Treasury;
        actions[10] = ActionContract.CalculationViews;
        actions[11] = ActionContract.VaultAction;
        actions[12] = ActionContract.VaultAccountAction;
        actions[13] = ActionContract.VaultLiquidationAction;
        actions[14] = ActionContract.VaultAccountHealth;

        (finalRouter, pauseRouter) = deployRouter(libs, actions);

        m = new MigratePrimeCash(
            nProxy(payable(address(NOTIONAL))).getImplementation(),
            address(pauseRouter),
            NOTIONAL
        );
    }

//     function deployPrimeCashOracles() internal usingAccount(DEPLOYER) { 

//     }

//     function setMigrationSettings() internal usingAccount(MANAGER) { 

//     }

//     function checkAllAccounts() internal usingAccount(DEPLOYER) { 

//     }

//     function setupMigration() internal usingAccount(NOTIONAL.owner()) { 
//         NOTIONAL.setPauseRouterAndGuardian(pauseRouter, guardian);
//         NOTIONAL.transferOwnership(patchFix, false);
//     }

//     function updateTotalDebt() internal usingAccount(MANAGER) { 
//         patchFix.updateTotalfCashDebt(...)
//     }

//     function emitAccountEventsAndUpgrade(Router finalRouter) internal usingAccount(MANAGER) {
//         patchFix.emitAccountEvents(accounts);
//         upgradeTo(finalRouter);
//     }

    function run() public {
        // TODO: upgrade router and mark down reserves
        // TODO: push out vault user profits

        // vm.prank(DEPLOYER);
        // EmptyProxy emptyImpl = new EmptyProxy()
        // deployBeacons(emptyImpl);

        deployMigratePrimeCash();
        // deployPrimeCashOracles();
        // deployWrappedFCash();

        // setMigrationSettings();
        // checkAllAccounts();
        // setupMigration();

        // // Begins migration
        // vm.prank(NOTIONAL.owner());
        // NOTIONAL.upgradeTo(pauseRouter);

        // executeMigration();

        // TODO: test rebalancing nwTokens down to zero
    }

//     function executeMigration() internal usingAccount(MANAGER) {
//         // Update total debt if required
//         updateTotalDebt();

//         // Runs upgrade and ends up in paused state again
//         patchFix.atomicPatchAndUpgrade();

//         // Inside paused state
//         checkUpgradeValidity();

//         // Emit all account events
//         emitAccountEventsAndUpgrade(finalRouter);
//     }
}