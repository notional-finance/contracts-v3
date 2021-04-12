import math

import pytest
from brownie.network.state import Chain
from tests.constants import SETTLEMENT_DATE, START_TIME
from tests.helpers import (
    get_cash_group_with_max_markets,
    get_eth_rate_mapping,
    get_fcash_token,
    get_liquidity_token,
    get_market_curve,
)

chain = Chain()


@pytest.fixture(scope="module", autouse=True)
def ethAggregators(MockAggregator, accounts):
    return [
        MockAggregator.deploy(18, {"from": accounts[0]}),
        MockAggregator.deploy(18, {"from": accounts[0]}),
        MockAggregator.deploy(18, {"from": accounts[0]}),
    ]


@pytest.fixture(scope="module", autouse=True)
def liquidation(
    MockLocalLiquidation,
    SettleAssetsExternal,
    MockCToken,
    cTokenAggregator,
    ethAggregators,
    accounts,
):
    SettleAssetsExternal.deploy({"from": accounts[0]})
    liq = accounts[0].deploy(MockLocalLiquidation)
    ctoken = accounts[0].deploy(MockCToken, 8)
    # This is the identity rate
    ctoken.setAnswer(1e18)
    aggregator = cTokenAggregator.deploy(ctoken.address, {"from": accounts[0]})

    rateStorage = (aggregator.address, 8)
    liq.setAssetRateMapping(1, rateStorage)
    cg = get_cash_group_with_max_markets(3)
    liq.setCashGroup(1, cg)
    ethAggregators[0].setAnswer(1e18)
    liq.setETHRateMapping(1, get_eth_rate_mapping(ethAggregators[0], discount=104))

    liq.setAssetRateMapping(2, rateStorage)
    liq.setCashGroup(2, cg)
    ethAggregators[1].setAnswer(1e18)
    liq.setETHRateMapping(2, get_eth_rate_mapping(ethAggregators[1], discount=102))

    liq.setAssetRateMapping(3, rateStorage)
    liq.setCashGroup(3, cg)
    ethAggregators[2].setAnswer(1e18)
    liq.setETHRateMapping(3, get_eth_rate_mapping(ethAggregators[2], discount=105))

    chain.mine(1, timestamp=START_TIME)

    return liq


@pytest.fixture(autouse=True)
def isolation(fn_isolation):
    pass


def test_liquidate_tokens_insufficient_no_fcash(liquidation, accounts):
    liquidityTokenNotional = 1000e8
    # tokenHaircut = 99

    markets = get_market_curve(3, "flat")
    for m in markets:
        liquidation.setMarketStorage(1, SETTLEMENT_DATE, m)

    liquidation.setPortfolio(accounts[0], [get_liquidity_token(1, notional=liquidityTokenNotional)])
    liquidation.setBalance(accounts[0], 1, -5000e8, 0)

    (balanceState, incentivePaid, portfolioState, newMarkets) = liquidation.liquidateLocalCurrency(
        accounts[0], 1, 0, START_TIME
    ).return_value

    # all liquidity tokens have been removed
    fCashClaim = math.trunc(markets[0][2] * liquidityTokenNotional / markets[0][4])
    cashClaim = math.trunc(markets[0][3] * liquidityTokenNotional / markets[0][4])

    # Liquidity token deleted
    assert portfolioState[0][0][-1] == 2
    assert portfolioState[1][0] == get_fcash_token(1, notional=fCashClaim)
    assert cashClaim == balanceState[3] - incentivePaid

    # assert market updates
    assert newMarkets[0][2] + fCashClaim == markets[0][2]
    assert newMarkets[0][3] + cashClaim == markets[0][3]
    assert newMarkets[0][4] + liquidityTokenNotional == markets[0][4]


def test_liquidate_tokens_insufficient_with_fcash(liquidation, accounts):
    liquidityTokenNotional = 1000e8
    fCashNotional = -500e8
    # tokenHaircut = 99

    markets = get_market_curve(3, "flat")
    for m in markets:
        liquidation.setMarketStorage(1, SETTLEMENT_DATE, m)

    liquidation.setPortfolio(
        accounts[0],
        [
            get_liquidity_token(1, notional=liquidityTokenNotional),
            get_fcash_token(1, notional=fCashNotional),
        ],
    )
    liquidation.setBalance(accounts[0], 1, -5000e8, 0)

    (balanceState, incentivePaid, portfolioState, newMarkets) = liquidation.liquidateLocalCurrency(
        accounts[0], 1, 0, START_TIME
    ).return_value

    # all liquidity tokens have been removed
    fCashClaim = math.trunc(markets[0][2] * liquidityTokenNotional / markets[0][4])
    cashClaim = math.trunc(markets[0][3] * liquidityTokenNotional / markets[0][4])

    # fCash updated with fCashClaim
    assert portfolioState[0][0] == get_fcash_token(
        1,
        notional=(fCashClaim + fCashNotional),
        storageState=1,
        storageSlot=portfolioState[0][0][4],
    )
    # Liquidity token deleted
    assert portfolioState[0][1][-1] == 2
    assert cashClaim == balanceState[3] - incentivePaid

    # assert market updates
    assert newMarkets[0][2] + fCashClaim == markets[0][2]
    assert newMarkets[0][3] + cashClaim == markets[0][3]
    assert newMarkets[0][4] + liquidityTokenNotional == markets[0][4]


def test_liquidate_tokens_sufficient_no_fcash(liquidation, accounts):
    liquidityTokenNotional = 1000e8
    # tokenHaircut = 99

    markets = get_market_curve(3, "flat")
    for m in markets:
        liquidation.setMarketStorage(1, SETTLEMENT_DATE, m)

    liquidation.setPortfolio(accounts[0], [get_liquidity_token(1, notional=liquidityTokenNotional)])
    liquidation.setBalance(accounts[0], 1, -990e8, 0)

    (balanceState, incentivePaid, portfolioState, newMarkets) = liquidation.liquidateLocalCurrency(
        accounts[0], 1, 0, START_TIME
    ).return_value

    # cashClaim = math.trunc(markets[0][3] * liquidityTokenNotional / markets[0][4])
    # netCashIncrease = cashClaim * (100 - tokenHaircut) / 100
    # tokenRemoved = math.trunc(liquidityTokenNotional * factors[0] / netCashIncrease)
    tokensRemoved = liquidityTokenNotional - portfolioState[0][0][3]

    # all liquidity tokens have been removed
    fCashClaim = math.trunc(markets[0][2] * tokensRemoved / markets[0][4])
    cashClaimRemoved = math.trunc(markets[0][3] * tokensRemoved / markets[0][4])

    assert pytest.approx(portfolioState[1][0][3], abs=2) == fCashClaim
    assert pytest.approx(cashClaimRemoved, abs=2) == balanceState[3] - incentivePaid

    # assert market updates
    assert pytest.approx(newMarkets[0][2] + fCashClaim, abs=2) == markets[0][2]
    assert pytest.approx(newMarkets[0][3] + cashClaimRemoved, abs=2) == markets[0][3]
    assert pytest.approx(newMarkets[0][4] + tokensRemoved, abs=2) == markets[0][4]


def test_liquidate_tokens_sufficient_with_fcash(liquidation, accounts):
    liquidityTokenNotional = 1000e8
    fCashNotional = -500e8
    # tokenHaircut = 99

    markets = get_market_curve(3, "flat")
    for m in markets:
        liquidation.setMarketStorage(1, SETTLEMENT_DATE, m)

    liquidation.setPortfolio(
        accounts[0],
        [
            get_liquidity_token(1, notional=liquidityTokenNotional),
            get_fcash_token(1, notional=fCashNotional),
        ],
    )
    liquidation.setBalance(accounts[0], 1, -490e8, 0)

    (balanceState, incentivePaid, portfolioState, newMarkets) = liquidation.liquidateLocalCurrency(
        accounts[0], 1, 0, START_TIME
    ).return_value

    # cashClaim = math.trunc(markets[0][3] * liquidityTokenNotional / markets[0][4])
    # netCashIncrease = cashClaim * (100 - tokenHaircut) / 100
    # tokensToRemove = math.trunc(liquidityTokenNotional * factors[0] / netCashIncrease)
    tokensRemoved = liquidityTokenNotional - portfolioState[0][1][3]

    # all liquidity tokens have been removed
    fCashClaim = math.trunc(markets[0][2] * tokensRemoved / markets[0][4])
    cashClaimRemoved = math.trunc(markets[0][3] * tokensRemoved / markets[0][4])

    assert pytest.approx(portfolioState[0][0][3], abs=2) == fCashClaim + fCashNotional
    assert pytest.approx(cashClaimRemoved, abs=2) == balanceState[3] - incentivePaid

    # assert market updates
    assert pytest.approx(newMarkets[0][2] + fCashClaim, abs=2) == markets[0][2]
    assert pytest.approx(newMarkets[0][3] + cashClaimRemoved, abs=2) == markets[0][3]
    assert pytest.approx(newMarkets[0][4] + tokensRemoved, abs=2) == markets[0][4]


# TODO: test with two tokens