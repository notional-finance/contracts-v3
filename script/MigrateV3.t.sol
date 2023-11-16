// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;
pragma abicoder v2;

import "forge-std/Script.sol";
import { UpgradeRouter } from "./utils/UpgradeRouter.s.sol";
import { InitialSettings } from "./InitialSettings.sol";

import { Deployments } from "@notional-v3/global/Deployments.sol";
import { Token } from "@notional-v3/global/Types.sol";

import { MigratePrimeCash } from "@notional-v3/external/patchfix/MigratePrimeCash.sol";
import { MigrationSettings } from "@notional-v3/external/patchfix/migrate-v3/MigrationSettings.sol";
import { PauseRouter } from "@notional-v3/external/PauseRouter.sol";
import { Router } from "@notional-v3/external/Router.sol";

import { nTokenERC20Proxy } from "@notional-v3/external/proxies/nTokenERC20Proxy.sol";
import { PrimeCashProxy } from "@notional-v3/external/proxies/PrimeCashProxy.sol";
import { PrimeDebtProxy } from "@notional-v3/external/proxies/PrimeDebtProxy.sol";

import { 
    CompoundV2HoldingsOracle,
    CompoundV2DeploymentParams
} from "@notional-v3/external/pCash/CompoundV2HoldingsOracle.sol";

import { nProxy } from "../contracts/proxy/nProxy.sol";
import { UpgradeableBeacon } from "../contracts/proxy/beacon/UpgradeableBeacon.sol";
import { EmptyProxy } from "../contracts/proxy/EmptyProxy.sol";

contract MigrateToV3 is UpgradeRouter {
    address BEACON_DEPLOYER = 0x0D251Bd6c14e02d34f68BFCB02c54cBa3D108122;
    address DEPLOYER = 0x8B64fA5Fd129df9c755eB82dB1e16D6D0Bdf5Bc3;
    address MANAGER = 0x02479BFC7Dce53A02e26fE7baea45a0852CB0909;

    uint16 internal constant ETH = 1;
    uint16 internal constant DAI = 2;
    uint16 internal constant USDC = 3;
    uint16 internal constant WBTC = 4;

    UpgradeableBeacon nTokenBeacon;
    UpgradeableBeacon pCashBeacon;
    UpgradeableBeacon pDebtBeacon;

    modifier usingAccount(address account) {
        vm.startPrank(account);
        _;
        vm.stopPrank();
    }

    function deployBeacons() internal usingAccount(BEACON_DEPLOYER) {
        // NOTE: the initial implementation can be any contract
        nTokenBeacon = new UpgradeableBeacon(MANAGER);
        require(address(nTokenBeacon) == address(Deployments.NTOKEN_BEACON));
        pCashBeacon = new UpgradeableBeacon(MANAGER);
        require(address(pCashBeacon) == address(Deployments.PCASH_BEACON));
        pDebtBeacon = new UpgradeableBeacon(MANAGER);
        require(address(pDebtBeacon) == address(Deployments.PDEBT_BEACON));

        address nTokenImpl = address(new nTokenERC20Proxy(NOTIONAL));
        address pCashImpl = address(new PrimeCashProxy(NOTIONAL));
        address pDebtImpl = address(new PrimeDebtProxy(NOTIONAL));

        nTokenBeacon.upgradeTo(nTokenImpl);
        pCashBeacon.upgradeTo(pCashImpl);
        pDebtBeacon.upgradeTo(pDebtImpl);

        nTokenBeacon.transferOwnership(address(NOTIONAL));
        pCashBeacon.transferOwnership(address(NOTIONAL));
        pDebtBeacon.transferOwnership(address(NOTIONAL));
    }

    function deployMigratePrimeCash() internal usingAccount(DEPLOYER) returns (
        MigrationSettings settings,
        MigratePrimeCash migrateRouter,
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

        settings = new MigrationSettings();
        migrateRouter = new MigratePrimeCash(settings, address(finalRouter), address(pauseRouter));
    }

    function deployPrimeCashOracles() internal usingAccount(DEPLOYER) returns (
        CompoundV2HoldingsOracle[] memory oracles
    ) {
        oracles = new CompoundV2HoldingsOracle[](4);
        {
            (Token memory assetToken, Token memory underlyingToken) = NOTIONAL.getCurrency(ETH);
            oracles[0] = new CompoundV2HoldingsOracle(CompoundV2DeploymentParams(
                NOTIONAL,
                underlyingToken.tokenAddress,
                assetToken.tokenAddress,
                assetToken.tokenAddress
            ));
        }
        {
            (Token memory assetToken, Token memory underlyingToken) = NOTIONAL.getCurrency(DAI);
            oracles[1] = new CompoundV2HoldingsOracle(CompoundV2DeploymentParams(
                NOTIONAL,
                underlyingToken.tokenAddress,
                assetToken.tokenAddress,
                assetToken.tokenAddress
            ));
        }
        {
            (Token memory assetToken, Token memory underlyingToken) = NOTIONAL.getCurrency(USDC);
            oracles[2] = new CompoundV2HoldingsOracle(CompoundV2DeploymentParams(
                NOTIONAL,
                underlyingToken.tokenAddress,
                assetToken.tokenAddress,
                assetToken.tokenAddress
            ));
        }
        {
            (Token memory assetToken, Token memory underlyingToken) = NOTIONAL.getCurrency(WBTC);
            oracles[3] = new CompoundV2HoldingsOracle(CompoundV2DeploymentParams(
                NOTIONAL,
                underlyingToken.tokenAddress,
                assetToken.tokenAddress,
                assetToken.tokenAddress
            ));
        }
    }

    function setMigrationSettings(
        MigrationSettings settings,
        CompoundV2HoldingsOracle[] memory oracles
    ) internal usingAccount(MANAGER) { 
        settings.setMigrationSettings(ETH, InitialSettings.getETH(oracles[0]));
        settings.setMigrationSettings(DAI, InitialSettings.getDAI(oracles[1]));
        settings.setMigrationSettings(USDC, InitialSettings.getUSDC(oracles[2]));
        settings.setMigrationSettings(WBTC, InitialSettings.getWBTC(oracles[3]));
    }

//     function checkAllAccounts() internal usingAccount(DEPLOYER) { 

//     }

//     function updateTotalDebt() internal usingAccount(MANAGER) { 
//         patchFix.updateTotalfCashDebt(...)
//     }

//     function checkUpgradeValidity() internal usingAccount(MANAGER) { 
//         patchFix.updateTotalfCashDebt(...)
//     }

//     function executeMigration() internal usingAccount(MANAGER) {
//         // Update total debt if required
//         updateTotalDebt();

//         // Runs upgrade and ends up in paused state again
//         patchFix.executeMigration();

//         // Inside paused state
//         checkUpgradeValidity();

//         // Emit all account events
//         emitAccountEventsAndUpgrade(finalRouter);
//     }

    function run() public {
        // TODO: mark down reserves
        // TODO: push out vault user profits
        // deployWrappedFCash();

        deployBeacons();
        (
            MigrationSettings settings,
            MigratePrimeCash migratePrimeCash,
            PauseRouter pauseRouter,
            Router finalRouter
        ) = deployMigratePrimeCash();
        CompoundV2HoldingsOracle[] memory oracles = deployPrimeCashOracles();

        setMigrationSettings(settings, oracles);
        // checkAllAccounts();

        // Begins migration
        vm.prank(NOTIONAL.owner());
        // Now we are paused but no migration
        NOTIONAL.upgradeTo(address(migratePrimeCash));

        // executeMigration();

        // TODO: test rebalancing nwTokens down to zero
    }

}