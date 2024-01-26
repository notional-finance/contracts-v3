import brownie
import pytest
from brownie.network.state import Chain
from brownie.test import given, strategy
from tests.constants import SECONDS_IN_QUARTER
from tests.helpers import (
    get_balance_action,
    get_balance_trade_action,
    get_interest_rate_curve,
    get_tref,
    initialize_environment,
    setup_residual_environment,
)
from tests.snapshot import EventChecker
from tests.stateful.invariants import check_system_invariants

chain = Chain()


@pytest.fixture(scope="module", autouse=True)
def environment(accounts):
    return initialize_environment(accounts)


@pytest.fixture(autouse=True)
def isolation(fn_isolation):
    pass


"""
Testing Matrix:

nToken State
1. cash, no liquid residuals, no ifCash residuals
2. no cash, no liquid residuals, no ifCash residuals
3. cash, no liquid residuals, negative ifCash residuals
4. no cash, no liquid residuals, negative ifCash residuals
5. cash, no liquid residuals, positive ifCash residuals
6. no cash, no liquid residuals, positive ifCash residuals

7. cash, liquid residuals (can't sell), no ifCash residuals
8. no cash, liquid residuals (can't sell), no ifCash residuals
9. cash, liquid residuals (can't sell), positive ifCash residuals
10. no cash, liquid residuals (can't sell), positive ifCash residuals
11. cash, liquid residuals (can't sell), negative ifCash residuals
12. no cash, liquid residuals (can't sell), negative ifCash residuals

13. cash, liquid residuals (can sell), no ifCash residuals
14. no cash, liquid residuals (can sell), no ifCash residuals
15. cash, liquid residuals (can sell), positive ifCash residuals
16. no cash, liquid residuals (can sell), positive ifCash residuals
17. cash, liquid residuals (can sell), negative ifCash residuals
18. no cash, liquid residuals (can sell), negative ifCash residuals

Results:
[User Option, State]
[(all), 1]: cash share
[(all), 2]: revert

1. batchBalance [True, False] sellfCash, no residuals
"""

class RedeemChecker():

    def find(self, events, maturity):
        f = [ e for e in events if e['maturity'] == maturity]
        if len(f) == 0:
            return None
        elif len(f) > 1:
            raise Exception("Multiple maturities")
        else:
            return f[0]

    def __init__(self, environment, account, currencyId):
        self.environment = environment
        self.account = account
        self.currencyId = currencyId

    def __enter__(self):
        nTokenAddress = self.environment.notional.nTokenAddress(self.currencyId)
        (nTokenPortfolio, ifCashAssets) = self.environment.notional.getNTokenPortfolio(nTokenAddress)
        markets = self.environment.notional.getActiveMarkets(self.currencyId)
        totalSupply = self.environment.nToken[self.currencyId].totalSupply()

        self.context = {
            'totalSupply': totalSupply,
            'balances': self.environment.notional.getAccountBalance(self.currencyId, self.account),
            'portfolio': self.environment.notional.getAccountPortfolio(self.account),
            'nTokenPortfolio': nTokenPortfolio,
            'ifCashAssets': ifCashAssets,
            'markets': markets
        }

        return self.context

    def __exit__(self, *_):
        pass

@given(
    residualType=strategy("uint8", min_value=0, max_value=2),
    marketResiduals=strategy("bool"),
    canSellResiduals=strategy("bool"),
    useAccountAction=strategy("bool")
)
def test_redeem_ntoken_batch_balance_action(
    environment, accounts, residualType, marketResiduals, canSellResiduals, useAccountAction
):
    currencyId = 2
    redeemAmount = 98_000e8 * environment.primeCashScalars["DAI"]
    setup_residual_environment(
        environment, accounts, residualType, marketResiduals, canSellResiduals
    )

    # Environment now has residuals, transfer some nTokens to clean account and attempt to redeem
    environment.nToken[currencyId].transfer(accounts[2], redeemAmount, {"from": accounts[0]})
    assert len(environment.notional.getAccountPortfolio(accounts[2])) == 0

    nTokenPV = environment.notional.nTokenPresentValueAssetDenominated(currencyId)
    totalSupply = environment.nToken[currencyId].totalSupply()
    action = get_balance_action(2, "RedeemNToken", depositActionAmount=redeemAmount)

    if not canSellResiduals and marketResiduals:
        with brownie.reverts():
            if useAccountAction:
                environment.notional.nTokenRedeem(
                    accounts[2].address, 2, redeemAmount, {"from": accounts[2]}
                )
            else: 
                environment.notional.batchBalanceAction(
                    accounts[2].address, [action], {"from": accounts[2]}
                )
    else:
        with EventChecker(environment, 'Redeem nToken', nTokensRedeemed=redeemAmount) as c:
            if useAccountAction:
                c['txn'] = environment.notional.nTokenRedeem(
                    accounts[2].address, 2, redeemAmount, {"from": accounts[2]}
                )
            else:
                c['txn'] = environment.notional.batchBalanceAction(
                    accounts[2].address, [action], {"from": accounts[2]}
                )

    # Account should have redeemed around the ifCash residual
    portfolio = environment.notional.getAccountPortfolio(accounts[2])
    assert len(portfolio) == 0

    # Test for PV of account[2] assets relative to redeem
    (cash, _, _) = environment.notional.getAccountBalance(2, accounts[2])
    cashRatio = cash / nTokenPV
    supplyRatio = redeemAmount / totalSupply

    if residualType == 0 and not marketResiduals:
        # In this scenario (with no residuals anywhere) valuation is at par
        assert pytest.approx(cashRatio, rel=1e-9) == supplyRatio
    else:
        assert cashRatio < supplyRatio

    check_system_invariants(environment, accounts)


def test_redeem_tokens_and_sell_fcash_zero_notional(environment, accounts):
    # This unit test is here to test a bug where markets were skipped during the sellfCash portion
    # of redeeming nTokens
    currencyId = 2
    cashGroup = list(environment.notional.getCashGroup(currencyId))
    # Enable the two year markets
    cashGroup[0] = 4
    environment.notional.updateCashGroup(currencyId, cashGroup)

    environment.notional.updateDepositParameters(
        currencyId, [0.4e8, 0.2e8, 0.2e8, 0.2e8], [0.8e9, 0.8e9, 0.8e9, 0.8e9]
    )

    environment.notional.updateInterestRateCurve(
        currencyId, [1, 2, 3, 4], [get_interest_rate_curve()] * 4
    )
    environment.notional.updateInitializationParameters(
        currencyId, [0] * 4, [0.5e9, 0.5e9, 0.5e9, 0.5e9]
    )

    blockTime = chain.time()
    chain.mine(1, timestamp=blockTime + SECONDS_IN_QUARTER)
    for (cid, _) in environment.nToken.items():
        try:
            environment.notional.initializeMarkets(cid, False)
        except Exception:
            pass

    collateral = get_balance_trade_action(1, "DepositUnderlying", [], depositActionAmount=10e18)
    action = get_balance_trade_action(
        2,
        "DepositUnderlying",
        [
            # This leaves a positive residual
            {"tradeActionType": "Borrow", "marketIndex": 3, "notional": 1e4, "maxSlippage": 0},
            # This leaves a negative residual
            {"tradeActionType": "Lend", "marketIndex": 4, "notional": 1e4, "minSlippage": 0},
        ],
        depositActionAmount=100e18,
        withdrawEntireCashBalance=True,
    )

    environment.notional.batchBalanceAndTradeAction(
        accounts[1], [collateral, action], {"from": accounts[1], "value": 10e18}
    )

    # Now settle the markets, should be some residual
    blockTime = chain.time()
    chain.mine(1, timestamp=blockTime + SECONDS_IN_QUARTER)
    for (cid, _) in environment.nToken.items():
        try:
            environment.notional.initializeMarkets(cid, False)
        except Exception:
            pass

    # Leaves some more residual
    action = get_balance_trade_action(
        2,
        "DepositUnderlying",
        [
            {"tradeActionType": "Borrow", "marketIndex": 1, "notional": 100e8, "maxSlippage": 0},
            {"tradeActionType": "Lend", "marketIndex": 2, "notional": 100e8, "minSlippage": 0},
            {"tradeActionType": "Lend", "marketIndex": 3, "notional": 100e8, "minSlippage": 0},
            {"tradeActionType": "Lend", "marketIndex": 4, "notional": 100e8, "minSlippage": 0},
        ],
        depositActionAmount=500e18,
        withdrawEntireCashBalance=True,
    )
    environment.notional.batchBalanceAndTradeAction(
        accounts[1], [collateral, action], {"from": accounts[1], "value": 10e18}
    )

    # Need to ensure that no residual assets are left behind
    assert len(environment.notional.getAccountPortfolio(accounts[0])) == 0
    with EventChecker(
        environment, 'Redeem nToken',
        nTokensRedeemed=1e8, 
        residuals=lambda x: len(x) > 0,
        maturities=[get_tref(chain.time()) + 8 * SECONDS_IN_QUARTER]
    ) as c:
        action = get_balance_action(2, "RedeemNToken", depositActionAmount=1e8)
        c['txn'] = environment.notional.batchBalanceAction(
            accounts[0].address, [action], {"from": accounts[0]}
        )

    assert len(environment.notional.getAccountPortfolio(accounts[0])) == 0
    check_system_invariants(environment, accounts)
