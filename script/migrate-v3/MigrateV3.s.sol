// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;
pragma abicoder v2;

import "forge-std/Script.sol";
import "forge-std/StdJson.sol";
import { UpgradeRouter } from "../utils/UpgradeRouter.s.sol";
import { InitialSettings } from "./InitialSettings.sol";

import { Constants } from "@notional-v3/global/Constants.sol";
import { Deployments } from "@notional-v3/global/Deployments.sol";
import { 
    Token,
    AccountBalance,
    PortfolioAsset,
    InterestRateCurveSettings,
    MarketParameters,
    PrimeCashFactors
} from "@notional-v3/global/Types.sol";

import { MigratePrimeCash, IERC20 } from "@notional-v3/external/patchfix/MigratePrimeCash.sol";
import {
    MigrationSettings,
    TotalfCashDebt,
    CurrencySettings
} from "@notional-v3/external/patchfix/migrate-v3/MigrationSettings.sol";
import { PauseRouter } from "@notional-v3/external/PauseRouter.sol";
import { Router } from "@notional-v3/external/Router.sol";

import { nTokenERC20Proxy } from "@notional-v3/external/proxies/nTokenERC20Proxy.sol";
import { PrimeCashProxy } from "@notional-v3/external/proxies/PrimeCashProxy.sol";
import { PrimeDebtProxy } from "@notional-v3/external/proxies/PrimeDebtProxy.sol";
import { InterestRateCurve } from "@notional-v3/internal/markets/InterestRateCurve.sol";

import { 
    CompoundV2HoldingsOracle,
    CompoundV2DeploymentParams
} from "@notional-v3/external/pCash/CompoundV2HoldingsOracle.sol";

import { nProxy } from "../../contracts/proxy/nProxy.sol";
import { UpgradeableBeacon } from "../../contracts/proxy/beacon/UpgradeableBeacon.sol";
import { EmptyProxy } from "../../contracts/proxy/EmptyProxy.sol";

interface NotionalV2 {

    // This is the V2 account context
    struct AccountContextOld {
        uint40 nextSettleTime;
        bytes1 hasDebt;
        uint8 assetArrayLength;
        uint16 bitmapCurrencyId;
        bytes18 activeCurrencies;
    }

    function getAccount(address account)
        external
        view
        returns (
            AccountContextOld memory accountContext,
            AccountBalance[] memory accountBalances,
            PortfolioAsset[] memory portfolio
        );
}

contract MigrateV3 is UpgradeRouter {
    using stdJson for string;

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

    mapping(uint256 => mapping(uint256 => int256)) public totalFCashDebt;
    mapping(uint256 => int256) public nTokenSupply;
    mapping(uint256 => int256) public cashBalance;

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

    function checkAllAccounts() internal { 
        string memory root = vm.projectRoot();
        string memory path = string(abi.encodePacked(root, "/script/migrate-v3/accounts.json"));
        string memory json = vm.readFile(path);
        // read file of all accounts
        address[] memory accounts = json.readAddressArray(".accounts");
        console.log("Found %s Accounts", accounts.length);

        bool foundError = false;
        for (uint256 i; i < accounts.length; i++) {
            bool err = _checkAccount(accounts[i]);
            foundError = foundError || err;
        }

        _checkNTokenAccount(ETH);
        _checkNTokenAccount(DAI);
        _checkNTokenAccount(USDC);
        _checkNTokenAccount(WBTC);
    }

    function _checkNTokenAccount(uint16 currencyId) private {
        address nTokenAddress = NOTIONAL.nTokenAddress(currencyId);
        (/* */, PortfolioAsset[] memory portfolio) = NOTIONAL.getNTokenPortfolio(nTokenAddress);
        (,uint256 totalSupply,,,,,,) = NOTIONAL.getNTokenAccount(nTokenAddress);

        for (uint256 i; i < portfolio.length; i++) {
            if (portfolio[i].notional < 0) {
                // Set total fCash debt balance here for validation later
                totalFCashDebt[portfolio[i].currencyId][portfolio[i].maturity] += portfolio[i].notional;
            }
        }

        require(totalSupply == uint256(nTokenSupply[currencyId]), "nToken supply");
    }

    function _checkAccount(address account) private returns (bool foundError) {
        (
            NotionalV2.AccountContextOld memory accountContext,
            AccountBalance[] memory accountBalances,
            PortfolioAsset[] memory portfolio
        ) = NotionalV2(address(NOTIONAL)).getAccount(account);
        foundError = false;

        if (
            accountContext.nextSettleTime != 0 &&
            accountContext.nextSettleTime < block.timestamp &&
            accountContext.bitmapCurrencyId == 0
        ) {
            console.log("Account %s has a matured next settle time", account);
            foundError = true;
        }

        for (uint256 i; i < accountBalances.length; i++) {
            if (accountBalances[i].currencyId == 0) break;
            nTokenSupply[accountBalances[i].currencyId] += accountBalances[i].nTokenBalance;

            if (accountBalances[i].cashBalance < 0) {
                console.log("Account %s has a negative cash balance %s in %s",
                    account, vm.toString(accountBalances[i].cashBalance), accountBalances[i].currencyId
                );
                foundError = true;
            } else {
                cashBalance[accountBalances[i].currencyId] += accountBalances[i].cashBalance;
            }

            // NOTE: this is not strictly necessary to check
            // if (accountBalances[i].lastClaimTime > 0) {
            //     console.log("Account %s has a last claim time in %s",
            //         account, accountBalances[i].currencyId
            //     );
            // }
        }

        for (uint256 i; i < portfolio.length; i++) {
            if (portfolio[i].maturity < block.timestamp) {
                console.log("Account %s has a matured asset in %s at %s",
                    account, portfolio[i].currencyId, portfolio[i].maturity
                );
                foundError = true;
            } else if (portfolio[i].notional < 0) {
                // Set total fCash debt balance here for validation later
                totalFCashDebt[portfolio[i].currencyId][portfolio[i].maturity] += portfolio[i].notional;
            }
        }
    }

    function getTotalDebts() internal view returns (TotalfCashDebt[][] memory) {
        string memory root = vm.projectRoot();
        string memory path = string(abi.encodePacked(root, "/script/migrate-v3/totalDebt.json"));
        string memory json = vm.readFile(path);
        bytes memory perCurrencyDebts = json.parseRaw(".debts");

        return abi.decode(perCurrencyDebts, (TotalfCashDebt[][]));
    }

    function updateTotalDebt(MigrationSettings settings) internal { 
        TotalfCashDebt[][] memory debts = getTotalDebts();
        settings.updateTotalfCashDebt(ETH, debts[0]);
        settings.updateTotalfCashDebt(DAI, debts[1]);
        settings.updateTotalfCashDebt(USDC, debts[2]);
        settings.updateTotalfCashDebt(WBTC, debts[3]);
    }

    function checkfCashCurve(MigrationSettings settings, uint16 currencyId) internal view {
        MarketParameters[] memory markets = NOTIONAL.getActiveMarkets(currencyId);
        CurrencySettings memory s = settings.getCurrencySettings(currencyId);
        (InterestRateCurveSettings[] memory finalCurves, uint256[] memory finalRates) = 
            settings.getfCashCurveUpdate(currencyId, false);

        console.log("** Check fCash Curve for %s **", currencyId);
        for (uint256 i; i < markets.length; i++) {
            uint256 maxRate = InterestRateCurve.calculateMaxRate(s.fCashCurves[i].maxRateUnits);
            console.log(
                "Market Index %s: %s [Initial Rate] %s [Final Rate]",
                i + 1, markets[i].lastImpliedRate, finalRates[i]
            );
            if (s.fCashCurves[i].kinkRate1 != finalCurves[i].kinkRate1) {
                console.log(
                    "Kink Rate 1: %s [Initial Rate] %s [Final Rate]",
                    maxRate * s.fCashCurves[i].kinkRate1 / 256,
                    maxRate * finalCurves[i].kinkRate1 / 256
                );
                console.logInt(
                    int256(maxRate * s.fCashCurves[i].kinkRate1 / 256) - int256(maxRate * finalCurves[i].kinkRate1 / 256)
                );
            } else {
                console.log(
                    "Kink Rate 2: %s [Initial Rate] %s [Final Rate]",
                    maxRate * s.fCashCurves[i].kinkRate2 / 256,
                    maxRate * finalCurves[i].kinkRate2 / 256
                );
                console.logInt(
                    int256(maxRate * s.fCashCurves[i].kinkRate2 / 256) - int256(maxRate * finalCurves[i].kinkRate2 / 256)
                );
            }
        }
    }

    function checkUpgradeValidity() internal { 
        // TODO: Check all system settings match expected
        // _checkGovernanceSettings();

        {
            // Check Total fCash invariant
            TotalfCashDebt[][] memory totalDebts = getTotalDebts();
            for (uint256 i; i < totalDebts.length; i++) {
                for (uint256 j; j < totalDebts[i].length; j++) {
                    TotalfCashDebt memory t = totalDebts[i][j];
                    (
                        int256 totalDebt,
                        int256 fCashReserve,
                        int256 pCashReserve
                    ) = NOTIONAL.getTotalfCashDebtOutstanding(uint16(i + 1), t.maturity);
                    require(fCashReserve == 0);
                    require(pCashReserve == 0);
                    require(-totalDebt == t.totalfCashDebt, "Does not match json");
                    // if (totalDebt != totalFCashDebt[i + 1][t.maturity]) {
                    //     console.log("Does not match storage %s %s", i + 1, t.maturity);
                    //     console.logInt(totalDebt);
                    //     console.logInt(totalFCashDebt[i + 1][t.maturity]);
                    require(totalDebt == totalFCashDebt[i + 1][t.maturity], "Does not match storage");
                    //}
                }
            }
        }

        // Check prime cash invariant
        _checkPrimeCashInvariant(ETH);
        _checkPrimeCashInvariant(DAI);
        _checkPrimeCashInvariant(USDC);
        _checkPrimeCashInvariant(WBTC);
    }

    function _checkPrimeCashInvariant(uint16 currencyId) internal view {
        // Cannot accrue prime interest while in paused state
        (/* */, PrimeCashFactors memory pr, /* */, uint256 totalUnderlyingSupply) =
            NOTIONAL.getPrimeFactors(currencyId, block.timestamp);
        (Token memory assetToken, Token memory underlyingToken) = NOTIONAL.getCurrency(currencyId);
        require(pr.totalPrimeSupply == IERC20(assetToken.tokenAddress).balanceOf(address(NOTIONAL)), "total prime supply");
        require(pr.totalPrimeDebt == 0);

        uint256 underlyingBalance = currencyId == ETH ?
            assetToken.tokenAddress.balance :
            IERC20(underlyingToken.tokenAddress).balanceOf(assetToken.tokenAddress);

        require(uint256(cashBalance[currencyId]) <= pr.totalPrimeSupply, "total cash balances");

        require(
            pr.lastTotalUnderlyingValue <=
            underlyingBalance * 1e8 / uint256(underlyingToken.decimals),
            "last underlying held vs assetToken balance"
        );
        // This value is converted to underlying using the prime rate and should match the
        // lastTotalUnderlyingValue
        requireAbsDiff(
            pr.lastTotalUnderlyingValue,
            totalUnderlyingSupply,
            1,
            "total underlying supply"
        );
    }

    function executeMigration(
        MigrationSettings settings
    ) internal usingAccount(MANAGER) {
        // Update total debt if required
        updateTotalDebt(settings);

        // Runs upgrade and ends up in paused state again
        MigratePrimeCash(address(NOTIONAL)).migratePrimeCash();

        // Inside paused state
        checkUpgradeValidity();

        // Emit all account events
        // emitAccountEventsAndUpgrade(finalRouter);
    }

    function run() public {
        // TODO: mark down reserves
        // TODO: push out vault user profits
        // deployWrappedFCash();

        // Set fork
        vm.createSelectFork(vm.envString("MAINNET_RPC_URL"), vm.envUint("FORK_BLOCK"));

        deployBeacons();
        (
            MigrationSettings settings,
            MigratePrimeCash migratePrimeCash,
            PauseRouter pauseRouter,
            Router finalRouter
        ) = deployMigratePrimeCash();
        CompoundV2HoldingsOracle[] memory oracles = deployPrimeCashOracles();

        setMigrationSettings(settings, oracles);
        checkAllAccounts();

        // Check curve settings, this has to happen before we run the upgrade
        checkfCashCurve(settings, ETH);
        checkfCashCurve(settings, DAI);
        checkfCashCurve(settings, USDC);
        checkfCashCurve(settings, WBTC);

        // Begins migration
        vm.prank(NOTIONAL.owner());
        // Now we are paused but no migration
        NOTIONAL.upgradeTo(address(migratePrimeCash));

        executeMigration(settings);

        // TODO: check that we can safely initialize markets
        uint256 timeRef = (block.timestamp - block.timestamp % Constants.QUARTER) + Constants.QUARTER;
        // TODO: test rebalancing nwTokens down to zero
    }

    function requireAbsDiff(uint256 a, uint256 b, uint256 abs, string memory m) internal pure {
        require(a < b ? b - a <= abs : a - b <= abs, m);
    }
}