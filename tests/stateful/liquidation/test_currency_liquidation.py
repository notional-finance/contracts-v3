import math

import pytest
from brownie import MockERC20
from brownie.network.state import Chain
from brownie.test import given, strategy
from liquidation_fixtures import *
from scripts.config import nTokenDefaults
from tests.helpers import get_balance_trade_action
from tests.snapshot import EventChecker

chain = Chain()


@pytest.fixture(autouse=True)
def isolation(fn_isolation):
    pass


def check_local_currency_liquidation(accounts, env, currencyId, assetsToAccount, assetsToLiquidator):
    fcBeforeNToken = env.notional.getFreeCollateral(accounts[2])
    (localPrimeCash, _) = env.notional.calculateLocalCurrencyLiquidation.call(
        accounts[2], currencyId, 0
    )
    localUnderlying = env.notional.convertCashBalanceToExternal(currencyId, localPrimeCash, True)

    if currencyId != 1:
        token = MockERC20.at(
            env.notional.getCurrency(currencyId)["underlyingToken"]["tokenAddress"]
        )

    if currencyId == 1:
        balanceBefore = accounts[0].balance()
    else:
        balanceBefore = token.balanceOf(accounts[0])

    with EventChecker(env, 'Liquidation',
        liquidator=accounts[0],
        account=accounts[2],
        localCurrency=currencyId,
        collateralCurrency=None,
        assetsToAccount=assetsToAccount,
        assetsToLiquidator=assetsToLiquidator
    ) as e:
        txn = env.notional.liquidateLocalCurrency(
            accounts[2],
            currencyId,
            0,
            {"from": accounts[0], "value": localUnderlying + 2e18 if currencyId == 1 else 0},
        )
        e['txn'] = txn

    assert txn.events["LiquidateLocalCurrency"]
    netLocal = txn.events["LiquidateLocalCurrency"]["netLocalFromLiquidator"]

    if currencyId == 1:
        balanceAfter = accounts[0].balance()
    else:
        balanceAfter = token.balanceOf(accounts[0])

    assert pytest.approx(netLocal, rel=1e-5) == localPrimeCash
    assert pytest.approx(balanceBefore - balanceAfter, rel=1e-5) == localUnderlying
    check_liquidation_invariants(env, accounts[2], fcBeforeNToken)

def setup_collateral_liquidation(env, accounts, currencyId, nTokenShare, cashShare):
    # Borrow local currency, deposit ETH collateral every time unless ETH is local
    symbol = list(filter(lambda x: env.currencyId[x] == currencyId, env.currencyId))[0]
    maturity = env.notional.getActiveMarkets(1)[0][1]

    if currencyId == 1:
        env.notional.depositUnderlyingToken(accounts[2], 2, 10_000e18, {"from": accounts[2]})
        cashBalance = env.notional.getAccountBalance(2, accounts[2])[0]
        cashAvailable = cashBalance - cashBalance * cashShare / 100
        nTokenAmount = cashAvailable * nTokenShare / 100
        fCashAmount = cashAvailable - nTokenAmount
        lendAction = [{
            "tradeActionType": "Lend",
            "marketIndex": 1,
            "notional": math.floor(env.notional.getfCashLendFromDeposit(
                2, fCashAmount, maturity, 0, chain.time(), False
            )['fCashAmount'] * 0.99),
            "minSlippage": 0,
        }] if fCashAmount > 0 else []

        if cashShare < 100:
            action = get_balance_trade_action(2, "ConvertCashToNToken", lendAction, depositActionAmount=nTokenAmount)
            env.notional.batchBalanceAndTradeAction(accounts[2], [action], {"from": accounts[2]})

        oracle = env.ethOracle["DAI"]
    else:
        env.notional.depositUnderlyingToken(
            accounts[2], 1, 100e18, {"from": accounts[2], "value": 100e18}
        )
        cashBalance = env.notional.getAccountBalance(1, accounts[2])[0]
        cashAvailable = cashBalance - cashBalance * cashShare / 100
        nTokenAmount = cashAvailable * nTokenShare / 100
        fCashAmount = cashAvailable - nTokenAmount
        lendAction = [{
            "tradeActionType": "Lend",
            "marketIndex": 1,
            "notional": math.floor(env.notional.getfCashLendFromDeposit(
                1, fCashAmount, maturity, 0, chain.time(), False
            )['fCashAmount'] * 0.99),
            "minSlippage": 0,
        }] if fCashAmount > 0 else []

        if cashShare < 100:
            action = get_balance_trade_action(
                1, "ConvertCashToNToken", lendAction, depositActionAmount=nTokenAmount
            )
            env.notional.batchBalanceAndTradeAction(accounts[2], [action], {"from": accounts[2]})

        oracle = env.ethOracle[symbol]

    # Borrowing up to the FC amount
    (fc, netLocal) = env.notional.getFreeCollateral(accounts[2])
    maxBorrowLocal = fc * 1e18 / oracle.latestAnswer() if currencyId != 1 else fc
    buffer = env.notional.getRateStorage(currencyId)["ethRate"]["buffer"]

    return (maxBorrowLocal, buffer, oracle)


def check_collateral_currency_liquidation(env, accounts, currencyId, oracle, assetsToAccount):
    collateralCurrency = 1 if currencyId != 1 else 2

    # Decrease ETH value
    if currencyId == 1:
        oracle.setAnswer(math.floor(oracle.latestAnswer() * 0.90))
    else:
        oracle.setAnswer(math.floor(oracle.latestAnswer() * 1.10))

    fcBefore = env.notional.getFreeCollateral(accounts[2])
    (
        netLocalCalculated,
        netCashCalculated,
        netNTokenCalculated,
    ) = env.notional.calculateCollateralCurrencyLiquidation.call(
        accounts[2], currencyId, collateralCurrency, 0, 0
    )
    localUnderlying = env.notional.convertCashBalanceToExternal(
        currencyId, netLocalCalculated, True
    )
    (accountCashBefore, _, _) = env.notional.getAccountBalance(collateralCurrency, accounts[2])

    if currencyId != 1:
        token = MockERC20.at(
            env.notional.getCurrency(currencyId)["underlyingToken"]["tokenAddress"]
        )

    if currencyId == 1:
        balanceBefore = accounts[0].balance()
    else:
        balanceBefore = token.balanceOf(accounts[0])

    balanceBeforeNToken = env.nToken[collateralCurrency].balanceOf(accounts[0])

    with EventChecker(env, 'Liquidation',
        liquidator=accounts[0],
        account=accounts[2],
        localCurrency=currencyId,
        collateralCurrency=collateralCurrency,
        assetsToAccount=assetsToAccount
    ) as e:
        txn = env.notional.liquidateCollateralCurrency(
            accounts[2],
            currencyId,
            collateralCurrency,
            0,
            0,
            True,
            True,
            {"from": accounts[0], "value": localUnderlying + 2e18 if currencyId == 1 else 0},
        )
        e['txn'] = txn

    assert txn.events["LiquidateCollateralCurrency"]
    netLocal = txn.events["LiquidateCollateralCurrency"]["netLocalFromLiquidator"]
    netCash = txn.events["LiquidateCollateralCurrency"]["netCollateralTransfer"]
    netNToken = txn.events["LiquidateCollateralCurrency"]["netNTokenTransfer"]

    if currencyId == 1:
        balanceAfter = accounts[0].balance()
    else:
        balanceAfter = token.balanceOf(accounts[0])

    balanceAfterNToken = env.nToken[collateralCurrency].balanceOf(accounts[0])
    (accountCashAfter, _, _) = env.notional.getAccountBalance(collateralCurrency, accounts[2])

    assert pytest.approx(netLocal, rel=1e-5) == netLocalCalculated
    assert pytest.approx(netCash, rel=1e-5) == netCashCalculated
    assert pytest.approx(netNToken, rel=1e-5) == netNTokenCalculated
    assert pytest.approx(balanceBefore - balanceAfter, rel=1e-5) == localUnderlying

    # If the account has insufficient cash then it is force to incur a negative cash balance
    assert pytest.approx(accountCashBefore - accountCashAfter, abs=100) == netCash
    if netCash > accountCashBefore:
        assert accountCashAfter < 0

    assert balanceAfterNToken - balanceBeforeNToken == netNToken

    check_liquidation_invariants(env, accounts[2], fcBefore)

    return (netNToken, netCash, netLocal)

@given(currencyId=strategy("uint", min_value=1, max_value=3))
def test_liquidate_local_currency_prime_ntoken(env, accounts, currencyId):
    decimals = env.notional.getCurrency(currencyId)["underlyingToken"]["decimals"]

    # Borrowing in prime cash to provide liquidity via nToken
    env.notional.enablePrimeBorrow(True, {"from": accounts[2]})
    depositActionAmount = 150.1 * decimals

    env.notional.depositUnderlyingToken(
        accounts[2],
        currencyId,
        depositActionAmount,
        {"from": accounts[2], "value": depositActionAmount if currencyId == 1 else 0},
    )
    cashBalance = env.notional.getAccountBalance(currencyId, accounts[2])[0]

    action = get_balance_trade_action(
        currencyId,
        "ConvertCashToNToken",
        [],
        depositActionAmount=cashBalance * 6.666,
        withdrawEntireCashBalance=False,
    )
    env.notional.batchBalanceAndTradeAction(accounts[2], [action], {"from": accounts[2]})
    # Undercollateralized after 45 days of debt accrual
    chain.mine(1, timedelta=86400 * 45)

    check_local_currency_liquidation(
        accounts, env, currencyId,
        lambda x: len(x) == 1 and x[0]['assetType'] == 'pCash' and x[0]['underlying'] == currencyId,
        lambda x: len(x) == 1 and x[0]['assetType'] == 'nToken' and x[0]['underlying'] == currencyId,
    )


@given(currencyId=strategy("uint", min_value=1, max_value=3))
def test_liquidate_local_currency_fcash_ntoken(env, accounts, currencyId):
    decimals = env.notional.getCurrency(currencyId)["underlyingToken"]["decimals"]

    # Borrowing and have nTokens in the same currency
    depositActionAmount = 27 * decimals
    action = get_balance_trade_action(
        currencyId,
        "DepositUnderlying",
        [{"tradeActionType": "Borrow", "marketIndex": 1, "notional": 100e8, "maxSlippage": 0}],
        depositActionAmount=depositActionAmount,
        withdrawEntireCashBalance=False,
    )
    env.notional.batchBalanceAndTradeAction(
        accounts[2],
        [action],
        {"from": accounts[2], "value": depositActionAmount if currencyId == 1 else 0},
    )

    action = get_balance_trade_action(
        currencyId,
        "ConvertCashToNToken",
        [],
        depositActionAmount=env.notional.getAccountBalance(currencyId, accounts[2])[0],
        withdrawEntireCashBalance=False,
    )
    env.notional.batchBalanceAndTradeAction(accounts[2], [action], {"from": accounts[2]})

    # Lower nToken haircut to put the account under, it's very difficult to simulate this
    # without multiple accounts
    tokenDefaults = nTokenDefaults["Collateral"]
    tokenDefaults[1] = 75
    env.notional.updateTokenCollateralParameters(currencyId, *(tokenDefaults))

    check_local_currency_liquidation(accounts, env, currencyId,
        lambda x: len(x) == 1 and x[0]['assetType'] == 'pCash' and x[0]['underlying'] == currencyId,
        lambda x: len(x) == 1 and x[0]['assetType'] == 'nToken' and x[0]['underlying'] == currencyId,
    )


@given(
    currencyId=strategy("uint", min_value=1, max_value=3),
    nTokenShare=strategy("uint", min_value=0, max_value=10),
    cashShare=strategy("uint", min_value=0, max_value=10),
)
def test_liquidate_collateral_currency_fcash(env, accounts, currencyId, nTokenShare, cashShare):
    (maxBorrowLocal, aggregateBuffer, oracle) = setup_collateral_liquidation(
        env, accounts, currencyId, nTokenShare * 10, cashShare * 10
    )

    fCashAmount = -math.floor(
        95
        * env.notional.getfCashAmountGivenCashAmount(currencyId, maxBorrowLocal, 1, chain.time())
        / aggregateBuffer
    )

    action = get_balance_trade_action(
        currencyId,
        "None",
        [
            {
                "tradeActionType": "Borrow",
                "marketIndex": 1,
                "notional": fCashAmount,
                "maxSlippage": 0,
            }
        ],
        withdrawEntireCashBalance=True,
        redeemToUnderlying=True,
    )
    env.notional.batchBalanceAndTradeAction(accounts[2], [action], {"from": accounts[2]})

    check_collateral_currency_liquidation(env, accounts, currencyId, oracle,
        lambda x: len(x) == 1 and x[0]['assetType'] == 'pCash' and x[0]['underlying'] == currencyId
    )

@given(
    currencyId=strategy("uint", min_value=1, max_value=3),
    nTokenShare=strategy("uint", min_value=0, max_value=10),
    cashShare=strategy("uint", min_value=0, max_value=10),
)
def test_liquidate_collateral_currency_prime(env, accounts, currencyId, nTokenShare, cashShare):
    decimals = env.notional.getCurrency(currencyId)["underlyingToken"]["decimals"]
    (maxBorrowLocal, aggregateBuffer, oracle) = setup_collateral_liquidation(
        env, accounts, currencyId, nTokenShare * 10, cashShare * 10
    )
    env.notional.enablePrimeBorrow(True, {"from": accounts[2]})

    maxBorrowUnderlying = math.floor(maxBorrowLocal * 99 / aggregateBuffer)
    maxBorrowPrimeCash = env.notional.convertUnderlyingToPrimeCash(
        currencyId, maxBorrowUnderlying * decimals / 1e8
    )
    env.notional.withdraw(currencyId, maxBorrowPrimeCash, True, {"from": accounts[2]})

    check_collateral_currency_liquidation(env, accounts, currencyId, oracle,
        lambda x: len(x) == 1 and x[0]['assetType'] == 'pCash' and x[0]['underlying'] == currencyId
    )

def test_liquidate_collateral_currency_over_supply_and_debt_cap(env, accounts):
    currencyId = 2
    (maxBorrowLocal, aggregateBuffer, oracle) = setup_collateral_liquidation(
        env, accounts, currencyId, 0, 0
    )

    fCashAmount = -math.floor(
        95
        * env.notional.getfCashAmountGivenCashAmount(currencyId, maxBorrowLocal, 1, chain.time())
        / aggregateBuffer
    )

    action = get_balance_trade_action(
        currencyId,
        "None",
        [
            {
                "tradeActionType": "Borrow",
                "marketIndex": 1,
                "notional": fCashAmount,
                "maxSlippage": 0,
            }
        ],
        withdrawEntireCashBalance=True,
        redeemToUnderlying=True,
    )
    env.notional.batchBalanceAndTradeAction(accounts[2], [action], {"from": accounts[2]})

    # Now put the collateral currency (ETH) at the debt cap and the supply cap
    factors = env.notional.getPrimeFactors(1, chain.time() + 1)
    # Have to buffer the max supply a bit to ensure that interest accrual does not
    # push this over the cap immediately
    maxSupply = factors['factors']['lastTotalUnderlyingValue'] + 1e8
    env.notional.setMaxUnderlyingSupply(1, maxSupply, 70)
    factors = env.notional.getPrimeFactors(1, chain.time() + 1)

    env.notional.enablePrimeBorrow(True, {"from": accounts[0]})
    maxPrimeCash = env.notional.convertUnderlyingToPrimeCash(1, factors['maxUnderlyingDebt'] * 1e10)
    env.notional.withdraw(1, maxPrimeCash - 0.1e8, True, {"from": accounts[0]})
    with brownie.reverts("Over Debt Cap"):
        env.notional.withdraw(1, 1e8, True, {"from": accounts[0]})

    # Should be able to liquidate still
    check_collateral_currency_liquidation(env, accounts, currencyId, oracle,
        lambda x: len(x) == 1 and x[0]['assetType'] == 'pCash' and x[0]['underlying'] == currencyId
    )