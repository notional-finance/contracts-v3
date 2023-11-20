// SPDX-License-Identifier: GPL-3.0-only
pragma solidity =0.7.6;
pragma abicoder v2;

import {
    InterestRateCurveSettings,
    InterestRateParameters,
    CashGroupSettings,
    MarketParameters,
    AssetRateStorage
} from "../../../global/Types.sol";
import {Constants} from "../../../global/Constants.sol";
import {SafeUint256} from "../../../math/SafeUint256.sol";
import {SafeInt256} from "../../../math/SafeInt256.sol";

import {NotionalProxy} from "../../../../interfaces/notional/NotionalProxy.sol";
import {IPrimeCashHoldingsOracle} from "../../../../interfaces/notional/IPrimeCashHoldingsOracle.sol";
import {InterestRateCurve} from "../../../internal/markets/InterestRateCurve.sol";

struct TotalfCashDebt {
    uint40 maturity;
    uint80 totalfCashDebt;
}

struct CurrencySettings {
    InterestRateCurveSettings primeDebtCurve;
    IPrimeCashHoldingsOracle primeCashOracle;
    CashGroupSettings cashGroupSettings;
    uint8 rateOracleTimeWindow5Min;
    bool allowPrimeDebt;
    string underlyingName;
    string underlyingSymbol;
    InterestRateCurveSettings[] fCashCurves;
    TotalfCashDebt[] fCashDebts;
}

contract MigrationSettings {
    using SafeUint256 for uint256;
    using SafeInt256 for int256;

    NotionalProxy internal constant NOTIONAL = NotionalProxy(0x1344A36A1B56144C3Bc62E7757377D288fDE0369);
    address internal constant NOTIONAL_MANAGER = 0x02479BFC7Dce53A02e26fE7baea45a0852CB0909;

    // @todo reduce this kink diff once we have more proper values for the tests
    uint256 internal constant MAX_KINK_DIFF = 250 * uint256(1e9 / 10000); // 250 * Constants.BASIS_POINT

    mapping(uint256 => CurrencySettings) internal currencySettings;

    function getCurrencySettings(uint256 currencyId) external view returns (CurrencySettings memory) {
        return currencySettings[currencyId];
    }

    /// @notice Sets migration settings for the given currency id
    function setMigrationSettings(uint256 currencyId, CurrencySettings memory settings) external {
        // Only the Notional manager can set migration settings
        require(msg.sender == NOTIONAL_MANAGER);

        CurrencySettings storage _storageSettings = currencySettings[currencyId];
        _storageSettings.primeDebtCurve = settings.primeDebtCurve;
        _storageSettings.primeCashOracle = settings.primeCashOracle;
        _storageSettings.cashGroupSettings = settings.cashGroupSettings;
        _storageSettings.allowPrimeDebt = settings.allowPrimeDebt;
        _storageSettings.underlyingName = settings.underlyingName;
        _storageSettings.underlyingSymbol = settings.underlyingSymbol;
        _storageSettings.rateOracleTimeWindow5Min = settings.rateOracleTimeWindow5Min;

        // Clear existing array
        uint256 existingLength = _storageSettings.fCashCurves.length;
        for (uint256 i; i < existingLength; i++)  _storageSettings.fCashCurves.pop();

        for (uint256 i; i < settings.fCashCurves.length; i++) {
            _storageSettings.fCashCurves.push(settings.fCashCurves[i]);
        }

        // Clear existing array
        existingLength = _storageSettings.fCashDebts.length;
        for (uint256 i; i < existingLength; i++)  _storageSettings.fCashDebts.pop();

        for (uint256 i; i < settings.fCashDebts.length; i++) {
            _storageSettings.fCashDebts.push(settings.fCashDebts[i]);
        }
    }

    /// @notice Special method for updating the total fCash debt since this may change as we
    /// closer to the actual upgrade
    function updateTotalfCashDebt(uint256 currencyId, TotalfCashDebt[] memory fCashDebts) external {
        // Allow the Notional Manager to set fCash debts closer to upgrade
        require(msg.sender == NOTIONAL_MANAGER);
        CurrencySettings storage _storageSettings = currencySettings[currencyId];

        // Clear existing array
        uint256 existingLength = _storageSettings.fCashDebts.length;
        for (uint256 i; i < existingLength; i++)  _storageSettings.fCashDebts.pop();

        for (uint256 i; i < fCashDebts.length; i++) {
            _storageSettings.fCashDebts.push(fCashDebts[i]);
        }
    }

    /// @notice Simulates the fCash curve update
    function getfCashCurveUpdate(uint16 currencyId, bool checkRateDiff) external view returns (
        InterestRateCurveSettings[] memory finalCurves,
        uint256[] memory finalRates
    ) {
        CurrencySettings memory settings = currencySettings[currencyId];
        (/* */, AssetRateStorage memory ar) = NOTIONAL.getRateStorage(currencyId);
        MarketParameters[] memory markets = NOTIONAL.getActiveMarkets(currencyId);

        // Use the original asset rates to calculate the cash to underlying exchange rates
        int256 assetRateDecimals = int256(10 ** (10 + ar.underlyingDecimalPlaces));
        int256 assetRate = address(ar.rateOracle) != address(0) ? 
            ar.rateOracle.getExchangeRateView() :
            // If rateOracle is not set then use the unit rate
            assetRateDecimals;

        return _calculateInterestRateCurves(
            settings.fCashCurves, markets, checkRateDiff, assetRateDecimals, assetRate
        );
    }

    function _calculateInterestRateCurves(
        InterestRateCurveSettings[] memory fCashCurves,
        MarketParameters[] memory markets,
        bool checkFinalRate,
        int256 assetRateDecimals,
        int256 assetRate
    ) internal view returns (InterestRateCurveSettings[] memory finalCurves, uint256[] memory finalRates) {
        // These will be the curves that are set in storage after this method exits
        finalCurves = new InterestRateCurveSettings[](fCashCurves.length);
        // This is just used for the external view method
        finalRates = new uint256[](fCashCurves.length);

        for (uint256 i = 0; i < fCashCurves.length; i++) {
            InterestRateCurveSettings memory irCurve = fCashCurves[i];
            MarketParameters memory market = markets[i];
            
            // Interest rate parameter object for local calculations
            uint256 maxRate = InterestRateCurve.calculateMaxRate(irCurve.maxRateUnits);
            InterestRateParameters memory irParams = InterestRateParameters({
                kinkUtilization1: uint256(irCurve.kinkUtilization1) * uint256(Constants.RATE_PRECISION / Constants.PERCENTAGE_DECIMALS),
                kinkUtilization2: uint256(irCurve.kinkUtilization2) * uint256(Constants.RATE_PRECISION / Constants.PERCENTAGE_DECIMALS),
                maxRate: maxRate,
                kinkRate1: maxRate * irCurve.kinkRate1 / 256,
                kinkRate2: maxRate * irCurve.kinkRate2 / 256,
                // Fees are not used in this method
                minFeeRate: 0, maxFeeRate: 0, feeRatePercent: 0
            });

            // Market utilization cannot change because cash / fCash is already set in the market
            uint256 utilization = InterestRateCurve.getfCashUtilization(
                0, market.totalfCash, market.totalPrimeCash.mul(assetRate).div(assetRateDecimals)
            );

            require(utilization < uint256(Constants.RATE_PRECISION), "Over Utilization");
            // Cannot overflow the new market's max rate
            require(market.lastImpliedRate < irParams.maxRate, "Over Max Rate");
            uint256 kinkMidpoint = (irParams.kinkUtilization2 - irParams.kinkUtilization1) / 2
                + irParams.kinkUtilization1;

            if (utilization <= irParams.kinkUtilization1) {
                // interestRate = (utilization * kinkRate1) / kinkUtilization1
                // kinkRate1 = (interestRate * kinkUtilization1) / utilization
                uint256 newKinkRate1 = market.lastImpliedRate
                    .mul(irParams.kinkUtilization1)
                    .div(utilization);
                require(newKinkRate1 < irParams.kinkRate2, "Over Kink Rate 2");

                // Check that the new curve's kink rate does not excessively diverge from the intended value
                if (checkFinalRate) {
                    require(_absDiff(newKinkRate1, irParams.kinkRate1) < MAX_KINK_DIFF, "Over Diff 1");
                }

                irParams.kinkRate1 = newKinkRate1;
                // Convert the interest rate back to the uint8 storage value
                irCurve.kinkRate1 = (newKinkRate1 * 256 / maxRate).toUint8();
            } else if (utilization < kinkMidpoint) { // Avoid divide by zero by using strictly less than
                // If we are below the kinkMidpoint then modify kinkRate1 to adjust the fCash curve.

                //                (utilization - kinkUtilization1) * (kinkRate2 - kinkRate1) 
                // interestRate = ---------------------------------------------------------- + kinkRate1
                //                            (kinkUtilization2 - kinkUtilization1)
                // ==> 
                //                interestRate * (kinkUtilization2 - kinkUtilization1) - kinkRate2 * (utilization - kinkUtilization1) 
                // kinkRate1 = ------------------------------------------------------------------------------------------------------
                //                                                      (1 - utilization - kinkUtilization1)
                uint256 numerator = market.lastImpliedRate
                    .mulInRatePrecision(irParams.kinkUtilization2.sub(irParams.kinkUtilization1))
                    .sub(irParams.kinkRate2.mulInRatePrecision(utilization.sub(irParams.kinkUtilization1)));
                uint256 denominator = irParams.kinkUtilization2 - utilization; // no overflow checked above
                uint256 newKinkRate1 = numerator.divInRatePrecision(denominator);
                require(newKinkRate1 < irParams.kinkRate2, "Over Kink Rate 2");

                if (checkFinalRate) {
                    require(_absDiff(newKinkRate1, irParams.kinkRate1) < MAX_KINK_DIFF, "Over Diff 2");
                }

                irParams.kinkRate1 = newKinkRate1;
                // Convert the interest rate back to the uint8 storage value
                irCurve.kinkRate1 = (newKinkRate1 * 256 / maxRate).toUint8();
            } else if (utilization < irParams.kinkUtilization2) { // Avoid divide by zero by using strictly less than
                // If above the kinkMidpoint but below kinkUtilization2, adjust kinkRate2
                //                (utilization - kinkUtilization1) * (kinkRate2 - kinkRate1) 
                // interestRate = ---------------------------------------------------------- + kinkRate1
                //                            (kinkUtilization2 - kinkUtilization1)
                // ==> 
                //                (interestRate - kinkRate1) * (kinkUtilization2 - kinkUtilization1) + kinkRate1 * (utilization - kinkUtilization1) 
                // kinkRate2 = -------------------------------------------------------------------------------------------------------------------
                //                                                      (utilization - kinkUtilization1)
                uint256 numerator = (market.lastImpliedRate.sub(irParams.kinkRate1))
                    .mulInRatePrecision(irParams.kinkUtilization2.sub(irParams.kinkUtilization1))
                    .add(irParams.kinkRate1.mulInRatePrecision(utilization.sub(irParams.kinkUtilization1)));
                uint256 denominator = utilization - irParams.kinkUtilization1; // no overflow checked above
                uint256 newKinkRate2 = numerator.divInRatePrecision(denominator);
                require(newKinkRate2 < irParams.maxRate, "Over Max Rate");

                if (checkFinalRate) {
                    require(_absDiff(newKinkRate2, irParams.kinkRate2) < MAX_KINK_DIFF, "Over Diff 2");
                }

                irParams.kinkRate2 = newKinkRate2;
                // Convert the interest rate back to the uint8 storage value
                irCurve.kinkRate2 = (newKinkRate2 * 256 / maxRate).toUint8();
            } else {
                //                (utilization - kinkUtilization2) * (maxRate - kinkRate2) 
                // interestRate = ---------------------------------------------------------- + kinkRate2
                //                                  (1 - kinkUtilization2)
                // ==> 
                //                interestRate * (1 - kinkUtilization2) - maxRate * (utilization - kinkUtilization2) 
                // kinkRate2 = ------------------------------------------------------------------------------------
                //                                          (1 - utilization)
                uint256 numerator = market.lastImpliedRate
                    .mulInRatePrecision(uint256(Constants.RATE_PRECISION).sub(irParams.kinkUtilization2))
                    .sub(irParams.maxRate.mulInRatePrecision(utilization.sub(irParams.kinkUtilization2)));
                uint256 denominator = uint256(Constants.RATE_PRECISION).sub(utilization);
                uint256 newKinkRate2 = numerator.divInRatePrecision(denominator);
                require(newKinkRate2 < irParams.maxRate, "Over Max Rate");

                if (checkFinalRate) {
                    require(_absDiff(newKinkRate2, irParams.kinkRate2) < MAX_KINK_DIFF, "Over Diff 3");
                }

                irParams.kinkRate2 = newKinkRate2;
                irCurve.kinkRate2 = (newKinkRate2 * 256 / maxRate).toUint8();
            }

            uint256 newInterestRate = InterestRateCurve.getInterestRate(irParams, utilization);
            if (checkFinalRate) {
                // Check that the next interest rate is very close to the current market rate
                require(_absDiff(newInterestRate, market.lastImpliedRate) < Constants.BASIS_POINT, "Over Final Diff");
            }
            finalCurves[i] = irCurve;
            finalRates[i] = newInterestRate;
        }
    }

    function _absDiff(uint256 a, uint256 b) private pure returns (uint256) {
        return a < b ? b - a : a - b;
    }
}