// SPDX-License-Identifier: MIT
pragma solidity >=0.7.6;
pragma abicoder v2;

import {NotionalBaseTest} from "../NotionalBaseTest.sol";

contract HarvestInterestTest is NotionalBaseTest {
    event AssetInterestHarvested(uint16 indexed currencyId, address assetToken, uint256 harvestAmount);

    uint16[] private allCurrencyIds;
    uint16 private maxCurrency;
    address private manager;
    address private notional;

    function setUp() public override {
        super.setUp();

        _setCurrencyToTest(3);
        _deployTreasuryAndViews();

        vm.startPrank(owner);
        manager = vm.addr(5);
        NOTIONAL.setTreasuryManager(manager);

        uint40 cooldown = 5 hours;
        for (uint16 i = 1; i <= maxCurrency; i++) {
            NOTIONAL.setRebalancingCooldown(i, cooldown);
        }
        maxCurrency = NOTIONAL.getMaxCurrencyId();
        allCurrencyIds = new uint16[](maxCurrency);
        for (uint16 i = 0; i < maxCurrency; i++) {
            allCurrencyIds[i] = i + 1;
        }
        vm.stopPrank();

        notional = address(NOTIONAL);
    }

    function test_RevertIf_NotManager() public {
        uint16[] memory currencyIds = _toUint16Array(CURRENCY_ID);

        vm.expectRevert("Treasury manager required");
        NOTIONAL.harvestAssetInterest(currencyIds);
    }

    function test_BalancesInAllStages() public {
        uint8 targetRate = 80;
        uint16[] memory currencyIds = _toUint16Array(CURRENCY_ID);

        uint256 startBalance = _actualBalanceOf(UNDERLYING, notional);
        uint256 startStoredBalance = _getStoredBalance(UNDERLYING);
        uint256 startABalance = _actualBalanceOf(ATOKEN, notional);
        uint256 managerBalance = _actualBalanceOf(ATOKEN, manager);

        assertEq(startBalance, startStoredBalance, "1");

        uint256 actualRate = _getActualRebalancingRate(CURRENCY_ID, targetRate);
        _setSingleTargetRateAndRebalance(CURRENCY_ID, ATOKEN, targetRate);

        uint256 afterRebBalance = _actualBalanceOf(UNDERLYING, notional);
        uint256 afterRebStoredBalance = _getStoredBalance(UNDERLYING);
        uint256 afterRebABalance = _actualBalanceOf(ATOKEN, notional);

        assertEq(afterRebBalance, afterRebStoredBalance, "2");

        uint256 rebalancedAmount = (startBalance * actualRate) / RATE_PRECISION;
        assertApproxEqAbs(startBalance, afterRebBalance + rebalancedAmount, _getRebalanceDelta(startBalance), "3");
        assertApproxEqAbs(
            startABalance + rebalancedAmount,
            afterRebABalance,
            _getRebalanceDelta(afterRebABalance),
            "4"
        );

        skip(30 * 24 * 60 * 60); // let interested be generated on Aave
        if (actualRate == 0) {
            assertEq(afterRebABalance, _actualBalanceOf(ATOKEN, notional), "Interested was generated");
        } else {
            assertLt(afterRebABalance, _actualBalanceOf(ATOKEN, notional), "Interested was not generated");
        }

        vm.prank(manager);
        NOTIONAL.harvestAssetInterest(currencyIds);

        uint256 endBalance = _actualBalanceOf(UNDERLYING, notional);
        uint256 endStoredBalance = _getStoredBalance(UNDERLYING);
        uint256 endABalance = _actualBalanceOf(ATOKEN, notional);
        uint256 endManagerBalance = _actualBalanceOf(ATOKEN, manager);

        assertEq(endBalance, endStoredBalance, "5");
        // TODO: check is this correct
        assertApproxEqAbs(
            endABalance,
            _getStoredBalance(ATOKEN),
            1,
            "After harvest, actual and stored balance should be eq"
        );
        assertEq(afterRebBalance, endBalance, "6");
        if (actualRate == 0) {
            assertEq(afterRebABalance, endABalance, "7.1");
            assertEq(managerBalance, endManagerBalance, "8.1");
        } else {
            assertGt(afterRebABalance, endABalance, "7.2");
            assertLt(managerBalance, endManagerBalance, "8.2");
        }
    }

    function test_harvestedAmount() public {
        uint8 targetRate = 95;

        uint256 startABalance = _actualBalanceOf(ATOKEN, notional);
        uint256 startAStoredBalance = _getStoredBalance(ATOKEN);
        uint256 managerABalance = _actualBalanceOf(ATOKEN, manager);
        uint256 startABalanceDiff = startABalance - startAStoredBalance;

        assertEq(managerABalance, 0, "1");
        assertEq(startABalanceDiff, 0, "2");

        uint256 actualRate = _getActualRebalancingRate(CURRENCY_ID, targetRate);
        _setSingleTargetRateAndRebalance(CURRENCY_ID, ATOKEN, targetRate);

        skip(4 weeks); // let interested be generated on Aave

        uint256 afterRebAStoredBalance = _getStoredBalance(ATOKEN);
        uint256 generatedInterest = _actualBalanceOf(ATOKEN, notional) - _getStoredBalance(ATOKEN);
        if (actualRate == 0) {
            assertEq(afterRebAStoredBalance, 0, "3.1");
            assertEq(generatedInterest, 0, "4.1");
        } else {
            assertGt(afterRebAStoredBalance, 0, "3.2");
            assertGt(generatedInterest, 0, "4.2");
        }

        if (actualRate != 0) {
            vm.expectEmit(true, true, false, false);
            emit AssetInterestHarvested(CURRENCY_ID, ATOKEN, generatedInterest);
        }

        vm.prank(manager);
        NOTIONAL.harvestAssetInterest(_toUint16Array(CURRENCY_ID));

        uint256 afterHarvestManagerABalance = _actualBalanceOf(ATOKEN, manager);

        assertEq(afterHarvestManagerABalance, generatedInterest, "5");
        assertEq(afterRebAStoredBalance, _getStoredBalance(ATOKEN), "6");
    }
}