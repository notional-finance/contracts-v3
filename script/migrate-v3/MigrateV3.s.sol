// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;
pragma abicoder v2;

import "forge-std/Test.sol";
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
    PrimeCashFactors,
    BalanceAction,
    BalanceActionWithTrades,
    DepositActionType,
    TradeActionType
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
import { Emitter } from "@notional-v3/internal/Emitter.sol";

import { 
    CompoundV2HoldingsOracle,
    CompoundV2DeploymentParams
} from "@notional-v3/external/pCash/CompoundV2HoldingsOracle.sol";

import { SafeInt256 } from "../../contracts/math/SafeInt256.sol";
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

contract MigrateV3 is UpgradeRouter, Test {
    using stdJson for string;
    using SafeInt256 for int256;

    event Transfer(address indexed from, address indexed to, uint256 value);

    address BEACON_DEPLOYER = 0x0D251Bd6c14e02d34f68BFCB02c54cBa3D108122;
    address DEPLOYER = 0x8B64fA5Fd129df9c755eB82dB1e16D6D0Bdf5Bc3;
    // address MANAGER = 0x02479BFC7Dce53A02e26fE7baea45a0852CB0909;
    // On Goerli:
    address MANAGER = 0xf862895976F693907f0AF8421Fe9264e559c2f6b;

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
    uint256[] public emitAccounts;

    // Checks event emission
    struct ExpectEmit {
        uint16 currencyId;
        uint256 erc1155Id;
        address account;
        uint256 value;
    }
    ExpectEmit[] public emitEvents;

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

        settings = new MigrationSettings(address(NOTIONAL), MANAGER);
        console.log("Final Router %s", address(finalRouter));
        migrateRouter = new MigratePrimeCash(
            settings,
            address(finalRouter),
            address(pauseRouter),
            MANAGER
        );
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

        // TODO: add emits here?

        require(totalSupply == uint256(nTokenSupply[currencyId]), "nToken supply");
    }

    function _checkAccount(address account) private returns (bool foundError) {
        (
            NotionalV2.AccountContextOld memory accountContext,
            AccountBalance[] memory accountBalances,
            PortfolioAsset[] memory portfolio
        ) = NotionalV2(address(NOTIONAL)).getAccount(account);
        foundError = false;
        uint256 emitData;

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

            if (accountBalances[i].cashBalance > 0 || accountBalances[i].nTokenBalance > 0) {
                emitData = emitData | uint256(bytes32((bytes1(0x01) << uint8(accountBalances[i].currencyId))));

                if (accountBalances[i].nTokenBalance > 0) {
                    emitEvents.push(
                        ExpectEmit(
                            0,
                            Emitter._legacyNTokenId(accountBalances[i].currencyId),
                            account,
                            accountBalances[i].nTokenBalance.toUint()
                        )
                    );
                }

                if (accountBalances[i].cashBalance > 0) {
                    emitEvents.push(
                        ExpectEmit(
                            accountBalances[i].currencyId,
                            0,
                            account,
                            accountBalances[i].cashBalance.toUint()
                        )
                    );
                }
            }

            // NOTE: this is not strictly necessary to check
            // if (accountBalances[i].lastClaimTime > 0) {
            //     console.log("Account %s has a last claim time in %s",
            //         account, accountBalances[i].currencyId
            //     );
            // }
        }

        if (portfolio.length > 0) {
            emitData = emitData | uint256(bytes32(bytes1(uint8(portfolio.length))) >> 8);
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

            if (portfolio[i].notional != 0) {
                emitEvents.push(
                    ExpectEmit(
                        0,
                        Emitter.encodefCashId(portfolio[i].currencyId, portfolio[i].maturity, portfolio[i].notional),
                        account,
                        portfolio[i].notional.abs().toUint()
                    )
                );
            }
        }

        if (emitData != 0) {
            emitData = emitData | uint256(uint160(account));
            emitAccounts.push(emitData);
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
        // NOTE: this fails and then we get a revert and etherscan blows up
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
                    require(totalDebt == totalFCashDebt[i + 1][t.maturity], "Does not match storage");
                }
            }
        }

        // Check prime cash invariant. ETH is not working on Goerli
        uint256 chainId;
        assembly { chainId := chainid() }
        if (chainId != 5) _checkPrimeCashInvariant(ETH);
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
        address pETH = NOTIONAL.pCashAddress(ETH);
        address pDAI = NOTIONAL.pCashAddress(DAI);
        address pUSDC = NOTIONAL.pCashAddress(USDC);
        address pWBTC = NOTIONAL.pCashAddress(WBTC);

        // Asserts that all the proper events are emitted
        console.log("Total Emit Events", emitEvents.length);
        for (uint256 i; i < emitEvents.length; i++) {
            ExpectEmit memory e = emitEvents[i];
            if (e.account == 0x60dE7F647dF2448eF17b9E0123411724De6e373D) continue;
            // // TODO: need to emit for nTokens as well...
            // if (e.account == 0xabc07BF91469C5450D6941dD0770E6E6761B90d6) continue;
            // if (e.account == 0x6EbcE2453398af200c688C7c4eBD479171231818) continue;
            // if (e.account == 0x18b0Fc5A233acF1586Da7C199Ca9E3f486305A29) continue;
            // if (e.account == 0x0Ace2DC3995aCD739aE5e0599E71A5524b93b886) continue;

            if (e.currencyId == ETH) {
                vm.expectEmit(true, true, true, true, pETH);
                emit Transfer(address(0), e.account, e.value);
            } else if (e.currencyId == DAI) {
                vm.expectEmit(true, true, true, true, pDAI);
                emit Transfer(address(0), e.account, e.value);
            } else if (e.currencyId == USDC) {
                vm.expectEmit(true, true, true, true, pUSDC);
                emit Transfer(address(0), e.account, e.value);
            } else if (e.currencyId == WBTC) {
                vm.expectEmit(true, true, true, true, pWBTC);
                emit Transfer(address(0), e.account, e.value);
            } else {
                vm.expectEmit(true, true, true, true, address(NOTIONAL));
                emit Emitter.TransferSingle(
                    address(MANAGER), address(0), e.account, e.erc1155Id, e.value
                );
            }
        }
        console.log("Emitting %s account events", emitAccounts.length);
        MigratePrimeCash(address(NOTIONAL)).emitAccountEvents(emitAccounts);

        // Upgrade to router
        MigratePrimeCash(address(NOTIONAL)).upgradeToRouter();
    }

    function setUp() public {
        // deployWrappedFCash();

        // Set fork
        vm.createSelectFork(vm.envString("GOERLI_RPC_URL"), vm.envUint("FORK_BLOCK"));

        // deployBeacons();
        // (
        //     MigrationSettings settings,
        //     MigratePrimeCash migratePrimeCash,
        //     PauseRouter pauseRouter,
        //     Router finalRouter
        // ) = deployMigratePrimeCash();
        // CompoundV2HoldingsOracle[] memory oracles = deployPrimeCashOracles();

        // New Router 0x6b986A60216ACA687457782aDFA0B002aD392Ce7
        // New Pause Router 0xFFd7531ED937F703B269815950cB75bdAAA341c9
        // Settings 0x5fbf4539A89fBd1E5d784DB3f7Ba6c394AC450fC
        // Migrate 0x6F4C6dC0340051EBFc1583Ca6A0c3ef5b94c50e0
        MigrationSettings settings = MigrationSettings(0x5fbf4539A89fBd1E5d784DB3f7Ba6c394AC450fC);
        MigratePrimeCash migratePrimeCash = MigratePrimeCash(0x6F4C6dC0340051EBFc1583Ca6A0c3ef5b94c50e0);
        CompoundV2HoldingsOracle[] memory oracles = new CompoundV2HoldingsOracle[](4);
        oracles[0] = CompoundV2HoldingsOracle(0xB12b08045c2FB403Fcae579641D0a011AAd8ED70);
        oracles[1] = CompoundV2HoldingsOracle(0xbe401d7e76bb71bf7fa5a4aed7F3b650C6E0bd25);
        oracles[2] = CompoundV2HoldingsOracle(0x123fCA954EA894305b684F56A0d043169a5aA7E4);
        oracles[3] = CompoundV2HoldingsOracle(0x1344A36A1B56144C3Bc62E7757377D288fDE0369);

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
    }

    function test_initializeMarkets() public {
        // Check that we can safely initialize markets
        uint256 timeRef = (block.timestamp - block.timestamp % Constants.QUARTER) + Constants.QUARTER;
        vm.warp(timeRef);
        NOTIONAL.initializeMarkets(ETH, false);
        NOTIONAL.initializeMarkets(DAI, false);
        NOTIONAL.initializeMarkets(USDC, false);
        NOTIONAL.initializeMarkets(WBTC, false);

        // TODO: test rebalancing nwTokens down to zero
    }

    function dealAndApprove(uint16 currencyId, address account) internal {
        (/* */, Token memory underlyingToken) = NOTIONAL.getCurrency(currencyId);
        if (currencyId == ETH) {
            vm.deal(account, 100_000e18);
        } else {
            deal(underlyingToken.tokenAddress, account, 100_000e18);

            vm.prank(account);
            IERC20(underlyingToken.tokenAddress).approve(address(NOTIONAL), type(uint256).max);
        }
    }

    function test_mintNTokens() public {
        address acct = makeAddr("account");
        dealAndApprove(ETH, acct);

        (/* */, int256 nTokenBalance, /* */) = NOTIONAL.getAccountBalance(ETH, acct);
        BalanceAction[] memory actions = new BalanceAction[](1);
        actions[0] = BalanceAction({
            actionType: DepositActionType.DepositUnderlyingAndMintNToken,
            currencyId: ETH,
            depositActionAmount: 1e18,
            withdrawAmountInternalPrecision: 0,
            withdrawEntireCashBalance: false,
            redeemToUnderlying: true
        });

        vm.prank(acct);
        NOTIONAL.batchBalanceAction{value: 1e18}(acct, actions);

        assertGe(nTokenBalance, 0, "Minted nTokens");
    }

    function test_lendfCash() public {
        address acct = makeAddr("account");
        dealAndApprove(ETH, acct);

        BalanceActionWithTrades[] memory actions = new BalanceActionWithTrades[](1);
        MarketParameters[] memory markets = NOTIONAL.getActiveMarkets(ETH);

        (/* */, /* */, /* */, bytes32 encodedTrade) = NOTIONAL.getDepositFromfCashLend(
            ETH, 1e8, markets[0].maturity, 0, block.timestamp
        );
        bytes32[] memory trades = new bytes32[](1);
        trades[0] = encodedTrade;

        actions[0] = BalanceActionWithTrades({
            actionType: DepositActionType.DepositUnderlying,
            currencyId: ETH,
            depositActionAmount: 1e18,
            withdrawAmountInternalPrecision: 0,
            withdrawEntireCashBalance: false,
            redeemToUnderlying: true,
            trades: trades
        });

        vm.prank(acct);
        NOTIONAL.batchBalanceAndTradeAction{value: 1e18}(acct, actions);
    }

    function requireAbsDiff(uint256 a, uint256 b, uint256 abs, string memory m) internal pure {
        require(a < b ? b - a <= abs : a - b <= abs, m);
    }
}