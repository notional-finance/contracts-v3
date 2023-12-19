// SPDX-License-Identifier: MIT
pragma solidity >=0.7.6;
pragma abicoder v2;

import {Deployments} from "../../contracts/global/Deployments.sol";
import {Constants} from "../../contracts/global/Constants.sol";
import {NotionalBaseTest} from "../NotionalBaseTest.sol";
import {RebalancingContextStorage} from "../../contracts/global/Types.sol";
import {IERC20} from "../../interfaces/IERC20.sol";
import {IPrimeCashHoldingsOracle} from "../../interfaces/notional/IPrimeCashHoldingsOracle.sol";

abstract contract RebalanceDefaultTest is NotionalBaseTest {
    function getUnderlyingInfo() internal view virtual returns (address underlying);

    function setUp() public override {
        super.setUp();

        _setCurrencyToTest(getUnderlyingInfo());
        _deployTreasuryAndViews();

        UNDERLYING = getUnderlyingInfo();
        CURRENCY_ID = _deployCurrency(UNDERLYING);

        ATOKEN = _getHoldings(CURRENCY_ID)[0];

        vm.prank(owner);
        NOTIONAL.setTreasuryManager(owner);
        labelDeployedContracts();
    }

    function testFork_RevertIf_NotRebalanceBot() public {
        vm.expectRevert("Unauthorized");
        NOTIONAL.rebalance(_toUint16Array(CURRENCY_ID));
    }

    function testFork_RevertIf_RebalanceBeforeCooldown() public {
        vm.startPrank(owner);
        NOTIONAL.setRebalancingCooldown(CURRENCY_ID, 5 hours);

        _setSingleTargetRateAndRebalance(CURRENCY_ID, ATOKEN, 80);

        vm.expectRevert();
        vm.startPrank(REBALANCE_BOT);
        NOTIONAL.rebalance(_toUint16Array(CURRENCY_ID));
    }

    function testFork_RebalanceAfterRebalanceCooldown() public {
        vm.startPrank(owner);
        NOTIONAL.setRebalancingCooldown(CURRENCY_ID, 5 hours);

        uint256 startBalance = _actualBalanceOf(UNDERLYING, address(NOTIONAL));
        uint256 startABalance = _actualBalanceOf(ATOKEN, address(NOTIONAL));

        uint256 targetRate = _getActualRebalancingRate(CURRENCY_ID, 80);
        _setSingleTargetRateAndRebalance(CURRENCY_ID, ATOKEN, 80);
        if (targetRate == 0) return;

        uint256 midBalance = _actualBalanceOf(UNDERLYING, address(NOTIONAL));

        assertGt(startBalance, _actualBalanceOf(UNDERLYING, address(NOTIONAL)), "1");
        assertLt(startABalance, _actualBalanceOf(ATOKEN, address(NOTIONAL)), "2");

        assertApproxEqAbs(
            startBalance,
            midBalance + (startBalance * targetRate) / RATE_PRECISION,
            _getRebalanceDelta(startBalance),
            "3"
        );
        (, , , RebalancingContextStorage memory context) = NOTIONAL.getRebalancingFactors(CURRENCY_ID);

        skip(context.rebalancingCooldownInSeconds + 1);

        uint256 midABalance = _actualBalanceOf(ATOKEN, address(NOTIONAL));

        uint256 newTargetRate = _getActualRebalancingRate(CURRENCY_ID, 50);
        _setSingleTargetRateAndRebalance(CURRENCY_ID, ATOKEN, 50);

        uint256 endBalance = _actualBalanceOf(UNDERLYING, address(NOTIONAL));
        uint256 endABalance = _actualBalanceOf(ATOKEN, address(NOTIONAL));

        assertApproxEqAbs(
            endBalance,
            startBalance - (startBalance * newTargetRate) / RATE_PRECISION,
            _getRebalanceDelta(endBalance),
            "4"
        );
        uint256 rateChange = (uint256(newTargetRate) * RATE_PRECISION) / uint256(targetRate);

        uint256 deltaA = _getRebalanceDelta(midABalance);
        assertApproxEqAbs(endABalance, (midABalance * rateChange) / RATE_PRECISION, deltaA, "5");
    }

    function testFork_CheckRebalanceAllCurrencies() public {
        vm.startPrank(owner);
        uint40 cooldown = 5 hours;
        uint16 maxCurrency = NOTIONAL.getMaxCurrencyId();

        for (uint16 i = 1; i <= maxCurrency; i++) {
            NOTIONAL.setRebalancingCooldown(i, cooldown);
        }
        vm.stopPrank();

        vm.startPrank(REBALANCE_BOT);
        (bool canExec, bytes memory execPayload) = NOTIONAL.checkRebalance();
        assertTrue(canExec, "Rebalance should be ready");

        // solhint-disable-next-line avoid-low-level-calls
        (bool success, ) = address(NOTIONAL).call(execPayload);
        assertTrue(success, "Rebalance should be executed successfully");

        (canExec, execPayload) = NOTIONAL.checkRebalance();
        assertFalse(canExec, "Rebalance should not be ready");
    }

    function testFork_checkRebalance_ShouldBeAbleToRebalanceIfLendingIsUnhealthy() public {
        uint40 cooldown = 5 hours;
        uint16 maxCurrency = NOTIONAL.getMaxCurrencyId();

        for (uint16 i = 1; i <= maxCurrency; i++) {
            vm.prank(owner);
            NOTIONAL.setRebalancingCooldown(i, cooldown);
            _setSingleTargetRateAndRebalance(CURRENCY_ID, ATOKEN, 80);
        }

        (bool canExec, bytes memory execPayload) = NOTIONAL.checkRebalance();
        assertFalse(canExec, "Rebalance should not be ready");

        // force external lending into unhealthy state
        address underlying = UNDERLYING;
        uint256 underlyingNotionalBalance;
        if (CURRENCY_ID == 1) {
            underlying = address(Deployments.WETH);
            underlyingNotionalBalance = address(NOTIONAL).balance;
        } else {
            underlyingNotionalBalance = IERC20(underlying).balanceOf(address(NOTIONAL));
        }
        vm.startPrank(ATOKEN);
        uint256 externalLend = IERC20(ATOKEN).balanceOf(address(NOTIONAL));
        uint256 availableForWithdrawOnAave = IERC20(underlying).balanceOf(ATOKEN);
        // leave half of what we lend on Aave available for withdraw
        IERC20(underlying).transfer(
            makeAddr("burn"),
            availableForWithdrawOnAave - externalLend / 2
        );
        vm.stopPrank();

        (canExec, execPayload) = NOTIONAL.checkRebalance();
        assertTrue(canExec, "Rebalance should be ready");

        vm.startPrank(REBALANCE_BOT);
        // solhint-disable-next-line avoid-low-level-calls
        (bool success, ) = address(NOTIONAL).call(execPayload);
        assertTrue(success, "Rebalance should be executed successfully");

        uint256 externalLendAfter = IERC20(ATOKEN).balanceOf(address(NOTIONAL));
        assertApproxEqAbs(externalLendAfter * 2, externalLend, externalLend / 10000, "1");
        uint256 underlyingNotionalBalanceAfter;
        if (CURRENCY_ID == 1) {
            underlyingNotionalBalanceAfter = address(NOTIONAL).balance;
        } else {
            underlyingNotionalBalanceAfter = IERC20(underlying).balanceOf(address(NOTIONAL));
        }
        assertApproxEqAbs(
            underlyingNotionalBalance + externalLend / 2,
            underlyingNotionalBalanceAfter,
            underlyingNotionalBalanceAfter / 10000,
            "2"
        );

        (canExec, execPayload) = NOTIONAL.checkRebalance();
        assertFalse(canExec, "Rebalance should not be ready");
    }

    function testFork_RebalanceShouldNotRevertWhenRedemptionFails() public {
        uint40 cooldown = 4 hours;
        vm.prank(owner);
        NOTIONAL.setRebalancingCooldown(CURRENCY_ID, cooldown);

        _setSingleTargetRateAndRebalance(CURRENCY_ID, ATOKEN, 95);
        skip(1 days);
        uint256 startBalance = _actualBalanceOf(UNDERLYING, address(NOTIONAL));
        // prevent redemption
        address underlying = CURRENCY_ID == 1 ? address(Deployments.WETH) : UNDERLYING;
        vm.startPrank(ATOKEN);
        uint256 onlyLeft = 100;
        IERC20(underlying).transfer(makeAddr("burn"), IERC20(underlying).balanceOf(ATOKEN) - onlyLeft);
        vm.stopPrank();

        _setSingleTargetRateAndRebalance(CURRENCY_ID, ATOKEN, 40);

        uint256 endBalance = _actualBalanceOf(UNDERLYING, address(NOTIONAL));
        assertEq(startBalance + onlyLeft, endBalance, "Balance should not change");
    }
}

contract RebalanceEthTest is RebalanceDefaultTest {
    function getUnderlyingInfo() internal pure override returns (address underlying) {
        underlying = 0x0000000000000000000000000000000000000000;
    }
}

contract RebalanceWBTCTest is RebalanceDefaultTest {
    function getUnderlyingInfo() internal pure override returns (address underlying) {
        underlying = 0x2f2a2543B76A4166549F7aaB2e75Bef0aefC5B0f;
    }
}

contract RebalanceDaiTest is RebalanceDefaultTest {
    function getUnderlyingInfo() internal pure override returns (address underlying) {
        underlying = 0xDA10009cBd5D07dd0CeCc66161FC93D7c9000da1;
    }
}

contract RebalanceAllTest is NotionalBaseTest {
    uint16[] internal currenciesLessThan8Decimals = [3, 4, 8];

    function setUp() public override {
        super.setUp();

        _deployTreasuryAndViews();
        _deployAllAaveOracles();

        owner = NOTIONAL.owner();
        vm.prank(owner);
        NOTIONAL.setTreasuryManager(owner);
    }

    function testForkFuzz_Rebalance(uint8 targetRate, uint16 _skip) public {
        targetRate = uint8(bound(uint256(targetRate), 0, uint256(99)));
        skip(_skip + 2);

        uint16 maxCurrency = _getMaxCurrency();
        for (uint16 currencyId = 1; currencyId <= maxCurrency; currencyId++) {
            IPrimeCashHoldingsOracle oracle = IPrimeCashHoldingsOracle(NOTIONAL.getPrimeCashHoldingsOracle(currencyId));
            address[] memory holdings = oracle.holdings();
            address underlyingToken = oracle.underlying();
            if (holdings.length == 0) {
                continue;
            }
            require(holdings.length == 1);

            uint256 startBalance = _actualBalanceOf(underlyingToken, address(NOTIONAL));
            uint256 startStoredBalance = _getStoredBalance(underlyingToken);
            uint256 startABalance = _actualBalanceOf(holdings[0], address(NOTIONAL));
            assertEq(startBalance, startStoredBalance, "1");

            uint256 actualRate = _getActualRebalancingRate(currencyId, targetRate);
            _setSingleTargetRateAndRebalance(currencyId, holdings[0], targetRate);

            uint256 newBalance = _actualBalanceOf(underlyingToken, address(NOTIONAL));
            uint256 newStoredBalance = _getStoredBalance(underlyingToken);
            uint256 newABalance = _actualBalanceOf(holdings[0], address(NOTIONAL));

            assertEq(newBalance, newStoredBalance, "2");

            uint256 delta = (startBalance * uint256(Constants.REBALANCING_UNDERLYING_DELTA_PERCENT)) /
                uint256(Constants.RATE_PRECISION);
            uint256 deltaA = (newABalance * uint256(Constants.REBALANCING_UNDERLYING_DELTA_PERCENT)) /
                uint256(Constants.RATE_PRECISION);
            assertApproxEqAbs(startBalance, newBalance + (startBalance * actualRate) / RATE_PRECISION, delta, "3");
            assertApproxEqAbs(startABalance + (startBalance * actualRate) / RATE_PRECISION, newABalance, deltaA, "4");
        }
    }

    function testForkFuzz_Rebalance_AaveOffByOneIssue(uint8[100] memory targetRates, uint16 _skip, uint256 ind) public {
        ind = bound(uint256(ind), 0, 2);

        uint16 currencyId = currenciesLessThan8Decimals[ind];
        for (uint256 i = 0; i < targetRates.length; i++) {
            uint8 targetRate = uint8(bound(uint256(targetRates[i]), 0, uint256(95)));

            skip(_skip + 1 hours);
            IPrimeCashHoldingsOracle oracle = IPrimeCashHoldingsOracle(NOTIONAL.getPrimeCashHoldingsOracle(currencyId));
            address[] memory holdings = oracle.holdings();
            _setSingleTargetRateAndRebalance(currencyId, holdings[0], targetRate);
        }
    }
}