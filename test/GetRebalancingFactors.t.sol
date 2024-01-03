// SPDX-License-Identifier: MIT
pragma solidity >=0.7.6;
pragma abicoder v2;

import {NotionalBaseTest} from "./NotionalBaseTest.sol";
import {RebalancingContextStorage} from "../contracts/global/Types.sol";
import {NotionalTreasury} from "../interfaces/notional/NotionalTreasury.sol";

abstract contract GetRebalancingFactorsTest is NotionalBaseTest {
    function _getCurrencyToTest() internal virtual returns (uint16);

    function setUp() public override {
        super.setUp();

        _deployTreasuryAndViews();
        _setCurrencyToTest(_getCurrencyToTest());
    }

    function test_getRebalancingFactors() public {
        (address holding, uint8 target, uint16 externalWithdrawThreshold, RebalancingContextStorage memory context) =
            NOTIONAL.getRebalancingFactors(CURRENCY_ID);

        assertEq(holding, ATOKEN);
        assertEq(uint256(context.rebalancingCooldownInSeconds), 0);
        assertEq(uint256(context.lastRebalanceTimestampInSeconds), 0);
        assertEqUint(target, 0);
        assertEqUint(externalWithdrawThreshold, 0);

        vm.startPrank(owner);
        NotionalTreasury.RebalancingTargetConfig[] memory targets = new NotionalTreasury.RebalancingTargetConfig[](1);
        targets[0] = NotionalTreasury.RebalancingTargetConfig(ATOKEN, 80, 120);
        NOTIONAL.setRebalancingTargets(CURRENCY_ID, targets);
        vm.stopPrank();

        (holding, target, externalWithdrawThreshold, context) = NOTIONAL.getRebalancingFactors(CURRENCY_ID);

        assertEq(holding, ATOKEN);
        assertEq(uint256(context.rebalancingCooldownInSeconds), 0);
        assertEq(uint256(context.lastRebalanceTimestampInSeconds), block.timestamp);
        assertEqUint(target, 80);
        assertEqUint(externalWithdrawThreshold, 120);
    }
}

contract GetRebalancingFactorsDaiTest is GetRebalancingFactorsTest {
    function _getCurrencyToTest() internal pure override returns (uint16) {
        return 2;
    }
}