// SPDX-License-Identifier: GPL-3.0-only
pragma solidity >=0.7.6;
pragma abicoder v2;

import {Constants} from "../contracts/global/Constants.sol";
import {TokenHandler} from "../contracts/internal/balances/TokenHandler.sol";
import {PrimeCashFactors, Token} from "../contracts/global/Types.sol";
import {IPrimeCashHoldingsOracle} from "../interfaces/notional/IPrimeCashHoldingsOracle.sol";
import {IERC20} from "../interfaces/IERC20.sol";
import {NotionalBaseTest} from "./NotionalBaseTest.sol";
import {SafeUint256} from "../contracts/math/SafeUint256.sol";

contract InvariantsTest is NotionalBaseTest {
    using SafeUint256 for uint256;
    using TokenHandler for Token;

    address private SENDER = vm.addr(653423423);
    uint16 private MAX_CURRENCY;

    function setUp() public override {
        super.setUp();

        _deployTreasuryAndViews();
        _deployAllAaveOracles();

        MAX_CURRENCY = NOTIONAL.getMaxCurrencyId();

        vm.label(SENDER, "SENDER");
        // labelDeployedContracts();
    }

    function _depositUnderlyingToken(uint16 currencyId, uint256 amount) internal {
        vm.startPrank(SENDER);
        uint256 maxActiveCurrenciesPerUser = 7;
        currencyId = uint16(bound(uint256(currencyId), 1, maxActiveCurrenciesPerUser));

        (,, uint256 maxSupply, uint256 totalSupply,,) = NOTIONAL.getPrimeFactors(currencyId, block.timestamp);
        if (maxSupply == 0) {
            return;
        }
        (, Token memory token) = NOTIONAL.getCurrency(currencyId);

        int256 max = (int256(maxSupply) - int256(totalSupply)) * 9999 / 10000;
        if (max < 2) {
            return;
        }
        amount = bound(amount, 2, uint256(max));
        amount = uint256(token.convertToExternal(int256(amount)));
        if (amount == 0) {
            return;
        }

        IPrimeCashHoldingsOracle oracle = IPrimeCashHoldingsOracle(NOTIONAL.getPrimeCashHoldingsOracle(currencyId));

        uint256 value;
        address underlyingToken = oracle.underlying();
        if (underlyingToken == address(0)) {
            deal(SENDER, amount);
            value = amount;
        } else {
            deal(underlyingToken, SENDER, amount);
            IERC20(underlyingToken).approve(address(NOTIONAL), amount);
        }

        (bool status,) = address(NOTIONAL).call{value: value}(
            abi.encodeWithSelector(NOTIONAL.depositUnderlyingToken.selector, SENDER, currencyId, amount)
        );
        require(status, "depositUnderlyingToken failed");
        vm.stopPrank();
    }

    function _withdraw(uint88 amount, uint16 currencyId, bool unwrap) internal {
        vm.startPrank(SENDER);
        currencyId = uint16(bound(uint256(currencyId), 1, uint256(MAX_CURRENCY)));
        (int256 maxAmount,,) = NOTIONAL.getAccountBalance(currencyId, SENDER);
        amount = uint88(bound(amount, 0, uint256(maxAmount)));
        if (amount == 0) {
            return;
        }

        NOTIONAL.withdraw(currencyId, amount, currencyId != 1 || unwrap);
        vm.stopPrank();
    }

    function _rebalance(uint16 currencyId, uint40 cooldown) internal {
        currencyId = uint16(bound(uint256(currencyId), 1, uint256(MAX_CURRENCY)));
        cooldown = uint40(bound(uint256(cooldown), 2 hours, 8 hours));

        skip(cooldown);
        (bool canExec, bytes memory execPayload) = NOTIONAL.checkRebalance();
        if (canExec) {
            vm.startPrank(REBALANCE_BOT);
            (bool status,) = address(NOTIONAL).call(execPayload);
            require(status, "rebalance failed");
        }
    }

    function _storedBalancesLeActualBalance() private {
        uint16 maxCurrency = _getMaxCurrency();
        for (uint16 currencyId = 1; currencyId <= maxCurrency; currencyId++) {
            address underlying = _getUnderlying(currencyId);

            if (currencyId == 1) {
                assertLe(_getStoredBalance(underlying), address(NOTIONAL).balance, "1");
            } else {
                assertLe(_getStoredBalance(underlying), IERC20(underlying).balanceOf(address(NOTIONAL)), "2");
            }

            address[] memory holdings = _getHoldings(currencyId);
            if (holdings.length == 0) {
                continue;
            }
            address token = holdings[0];
            assertLe(_getStoredBalance(token), IERC20(token).balanceOf(address(NOTIONAL)), "3");
        }
    }

    function _notInsolvent() private {
        uint16 maxCurrency = _getMaxCurrency();
        for (uint16 i = 1; i <= maxCurrency; i++) {
            NOTIONAL.accruePrimeInterest(i);
            PrimeCashFactors memory s = NOTIONAL.getPrimeFactorsStored(i);
            uint256 supply = s.supplyScalar.mul(s.underlyingScalar).mul(s.totalPrimeSupply);
            uint256 debt = s.debtScalar.mul(s.underlyingScalar).mul(s.totalPrimeDebt);
            uint256 underlying = (s.lastTotalUnderlyingValue + 1).mul(uint256(Constants.DOUBLE_SCALAR_PRECISION));

            assertLe(supply.sub(debt), underlying, "Insolvent");
        }
    }

    function testFuzz_NotInsolvent(
        uint16[100] memory currencyIds,
        uint256[100] memory depositAmounts,
        uint88[100] memory withdrawAmounts,
        uint40[100] memory cooldown,
        bool[100] memory unwraps,
        bool[100] memory first,
        bool[100] memory second,
        bool[100] memory third
    ) public {
        for (uint256 i = 0; i < 100; i++) {
            if (first[i]) {
                _depositUnderlyingToken(currencyIds[i], depositAmounts[i]);
            }
            if (second[i]){
                _withdraw(withdrawAmounts[i], currencyIds[i], unwraps[i]);
            }
            if (third[i]){
                _rebalance(currencyIds[i], cooldown[i]);
            }
        }

        _notInsolvent();
        _storedBalancesLeActualBalance();
    }
}
