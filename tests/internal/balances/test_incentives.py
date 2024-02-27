import pytest
from brownie.convert.datatypes import Wei
from brownie.test import given, strategy
from tests.constants import SECONDS_IN_DAY, SECONDS_IN_YEAR, START_TIME
from tests.helpers import get_balance_state


@pytest.mark.balances
class TestIncentives:
    @pytest.fixture(scope="module", autouse=True)
    def incentives(self, MockIncentives, accounts):
        mock = MockIncentives.deploy({"from": accounts[0]})
        mock.setNTokenAddress(1, accounts[9])

        return mock

    @pytest.fixture(autouse=True)
    def isolation(self, fn_isolation):
        pass

    @given(nTokensMinted=strategy("uint", min_value=1e8, max_value=1e18))
    def test_new_account_under_new_calculation(self, incentives, nTokensMinted, accounts):
        incentives.changeNTokenSupply(accounts[9], 100_000e8, START_TIME)
        incentives.setEmissionRate(accounts[9], 50_000, START_TIME)

        balanceState = get_balance_state(
            1, storedNTokenBalance=0, netNTokenSupplyChange=nTokensMinted
        )

        (incentivesToClaim, balanceState_) = incentives.calculateIncentivesToClaim(
            accounts[9], balanceState, START_TIME + SECONDS_IN_DAY, nTokensMinted
        )

        assert incentivesToClaim == 0
        # Last Claim Time
        assert balanceState_[7] == 0
        # Accumulated Reward Debt as one day's worth of tokens
        assert pytest.approx(balanceState_[8], abs=10) == Wei(
            nTokensMinted * (50_000e8 / 360) / 100_000e8
        )

    @given(timeSinceMigration=strategy("uint", min_value=0, max_value=SECONDS_IN_YEAR))
    def test_no_dilution_of_previous_incentives(self, incentives, accounts, timeSinceMigration):
        incentives.changeNTokenSupply(accounts[9], 100_000e8, START_TIME)
        incentives.setEmissionRate(accounts[9], 50_000, START_TIME)

        balanceStateMinnow = get_balance_state(
            1, storedNTokenBalance=100e8, netNTokenSupplyChange=0
        )

        balanceStateWhale = get_balance_state(
            1, storedNTokenBalance=0, netNTokenSupplyChange=100_000_000e8
        )

        # Calculate claim of the minnow first
        (incentivesToClaimMinnow1, _) = incentives.calculateIncentivesToClaim(
            accounts[9], balanceStateMinnow, START_TIME + timeSinceMigration, 100e8
        )

        # Whale now mints a lot of tokens
        incentives.changeNTokenSupply(accounts[9], 100_000_000e8, START_TIME + timeSinceMigration)

        (incentivesToClaimMinnow2, _) = incentives.calculateIncentivesToClaim(
            accounts[9], balanceStateMinnow, START_TIME + timeSinceMigration, 100e8
        )

        # Assert that this has not changed
        assert incentivesToClaimMinnow1 == incentivesToClaimMinnow2

        (incentivesToClaimWhale, _) = incentives.calculateIncentivesToClaim(
            accounts[9], balanceStateWhale, START_TIME + timeSinceMigration, 100_000_000e8
        )
        assert incentivesToClaimWhale == 0

        # Ensure that these incentives are still accumulating
        (incentivesToClaimMinnow3, _) = incentives.calculateIncentivesToClaim(
            accounts[9], balanceStateMinnow, START_TIME + timeSinceMigration + 100, 100e8
        )
        assert incentivesToClaimMinnow3 > incentivesToClaimMinnow2