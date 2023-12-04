// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;
pragma abicoder v2;

import "forge-std/Test.sol";

import { Router } from "../contracts/external/Router.sol";
import { BatchAction, BalanceActionWithTrades, BalanceAction } from "../contracts/external/actions/BatchAction.sol";
import "../interfaces/notional/NotionalProxy.sol";

contract RedeemNToken is Test {
    NotionalProxy constant NOTIONAL = NotionalProxy(0x1344A36A1B56144C3Bc62E7757377D288fDE0369);
    string ARBITRUM_RPC_URL = vm.envString("ARBITRUM_RPC_URL");
    uint256 ARBITRUM_FORK_BLOCK = 133312145;

    function getDeployedContracts() internal view returns (Router.DeployedContracts memory c) {
        Router r = Router(payable(address(NOTIONAL)));
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

    function upgradeTo(Router.DeployedContracts memory c) internal returns (Router r) {
        r = new Router(c);
        vm.prank(NOTIONAL.owner());
        NOTIONAL.upgradeTo(address(r));
    }

    function setUp() public {
        vm.createSelectFork(ARBITRUM_RPC_URL, ARBITRUM_FORK_BLOCK);
        Router.DeployedContracts memory c = getDeployedContracts();
        c.batchAction = address(new BatchAction());

        upgradeTo(c);
    }

    function test_RedeemResiduals() public {
        address acct = 0xd74e7325dFab7D7D1ecbf22e6E6874061C50f243;
        address acct2 = makeAddr("acct2");
        uint16 USDC = 1;
        vm.deal(acct, 10e18);
        (/* */, int256 nTokenBalance, /* */) = NOTIONAL.getAccountBalance(USDC, acct);
        address nToken = NOTIONAL.nTokenAddress(USDC);

        (/* */, PortfolioAsset[] memory netfCashAssetsBefore) = NOTIONAL.getNTokenPortfolio(nToken);
        MarketParameters[] memory marketsBefore = NOTIONAL.getActiveMarkets(USDC);
        // Move the last implied rate by borrowing
        bytes32[] memory trades = new bytes32[](1);
        trades[0] = bytes32(
            (uint256(uint8(1)) << 248) |
            (uint256(1) << 240) |
            (uint256(5e8) << 152) |
            (uint256(0) << 120)
        );
        BalanceActionWithTrades[] memory b = new BalanceActionWithTrades[](1);
        b[0] = BalanceActionWithTrades({
            actionType: DepositActionType.DepositUnderlying,
            currencyId: USDC,
            depositActionAmount: 10e18,
            withdrawAmountInternalPrecision: 0,
            withdrawEntireCashBalance: false,
            redeemToUnderlying: true,
            trades: trades
        });
        vm.deal(acct2, 25e18);
        vm.prank(acct2);
        NOTIONAL.batchBalanceAndTradeAction{value: 10e18}(acct2, b);


        vm.startPrank(acct);
        BalanceAction[] memory t = new BalanceAction[](1);
        t[0] = BalanceAction({
            actionType: DepositActionType.DepositUnderlyingAndMintNToken,
            currencyId: USDC,
            depositActionAmount: 1e18,
            withdrawAmountInternalPrecision: 0,
            withdrawEntireCashBalance: true,
            redeemToUnderlying: true
        });
        // t[0] = BalanceAction({
        //     actionType: DepositActionType.RedeemNToken,
        //     currencyId: USDC,
        //     depositActionAmount: uint256(nTokenBalance),
        //     withdrawAmountInternalPrecision: 0,
        //     withdrawEntireCashBalance: true,
        //     redeemToUnderlying: true
        // });
        console.log("Start Mint nToken");
        NOTIONAL.batchBalanceAction{value: 1e18}(acct, t);
        console.log("End Mint nToken");

        (/* */, PortfolioAsset[] memory netfCashAssetsAfter) = NOTIONAL.getNTokenPortfolio(nToken);
        MarketParameters[] memory marketsAfter = NOTIONAL.getActiveMarkets(USDC);

        // NOTE: the nToken's fCash position should be unchanged
        for (uint256 i; i < netfCashAssetsBefore.length; i++) {
            assertEq(
                netfCashAssetsBefore[i].notional + marketsBefore[i].totalfCash,
                netfCashAssetsAfter[i].notional + marketsAfter[i].totalfCash
            );
        }
    }
}