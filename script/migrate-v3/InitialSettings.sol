// SPDX-License-Identifier: GPL-3.0-only
pragma solidity =0.7.6;
pragma abicoder v2;

import {InterestRateCurveSettings, CashGroupSettings} from "../../contracts/global/Types.sol";
import {IPrimeCashHoldingsOracle} from "@notional-v3/interfaces/IPrimeCashHoldingsOracle.sol";
import {CurrencySettings, TotalfCashDebt} from "@notional-v3/external/patchfix/migrate-v3/MigrationSettings.sol";

library InitialSettings {

    function getETH(IPrimeCashHoldingsOracle oracle) internal pure returns (CurrencySettings memory) {
        InterestRateCurveSettings[] memory fCashCurves = new InterestRateCurveSettings[](2);
        fCashCurves[0] = InterestRateCurveSettings({
            kinkUtilization1: 15,
            kinkUtilization2: 70,
            kinkRate1: 17,
            kinkRate2: 51,
            maxRateUnits: 120,
            feeRatePercent: 8,
            minFeeRate5BPS: 3,
            maxFeeRate25BPS: 8
        });
        fCashCurves[1] = InterestRateCurveSettings({
            kinkUtilization1: 15,
            kinkUtilization2: 70,
            kinkRate1: 20,
            kinkRate2: 61,
            maxRateUnits: 100,
            feeRatePercent: 8,
            minFeeRate5BPS: 3,
            maxFeeRate25BPS: 8
        });

        InterestRateCurveSettings memory primeDebtCurve = InterestRateCurveSettings({
            kinkUtilization1: 15,
            kinkUtilization2: 70,
            kinkRate1: 2,
            kinkRate2: 8,
            maxRateUnits: 255,
            feeRatePercent: 20,
            minFeeRate5BPS: 10,
            maxFeeRate25BPS: 160
        });

        CashGroupSettings memory cashGroupSettings = CashGroupSettings({
            maxMarketIndex: 2,
            rateOracleTimeWindow5Min: 72,
            maxDiscountFactor5BPS: 40,
            reserveFeeShare: 80,
            debtBuffer25BPS: 22,
            fCashHaircut25BPS: 22,
            minOracleRate25BPS: 20,
            liquidationfCashHaircut25BPS: 6,
            liquidationDebtBuffer25BPS: 6,
            maxOracleRate25BPS: 28
        });

        return CurrencySettings({
            primeDebtCurve: primeDebtCurve,
            primeCashOracle: oracle,
            cashGroupSettings: cashGroupSettings,
            rateOracleTimeWindow5Min: 72,
            allowPrimeDebt: true,
            underlyingName: "Ether",
            underlyingSymbol: "ETH",
            fCashCurves: fCashCurves,
            fCashDebts: new TotalfCashDebt[](0)
        });
    }

    function getDAI(IPrimeCashHoldingsOracle oracle) internal pure returns (CurrencySettings memory) {
        InterestRateCurveSettings[] memory fCashCurves = new InterestRateCurveSettings[](3);
        fCashCurves[0] = InterestRateCurveSettings({
            kinkUtilization1: 15,
            kinkUtilization2: 70,
            kinkRate1: 17,
            kinkRate2: 51,
            maxRateUnits: 120,
            feeRatePercent: 8,
            minFeeRate5BPS: 3,
            maxFeeRate25BPS: 8
        });
        fCashCurves[1] = InterestRateCurveSettings({
            kinkUtilization1: 15,
            kinkUtilization2: 70,
            kinkRate1: 20,
            kinkRate2: 61,
            maxRateUnits: 100,
            feeRatePercent: 8,
            minFeeRate5BPS: 3,
            maxFeeRate25BPS: 8
        });
        fCashCurves[2] = InterestRateCurveSettings({
            kinkUtilization1: 15,
            kinkUtilization2: 70,
            kinkRate1: 20,
            kinkRate2: 61,
            maxRateUnits: 100,
            feeRatePercent: 8,
            minFeeRate5BPS: 3,
            maxFeeRate25BPS: 8
        });

        InterestRateCurveSettings memory primeDebtCurve = InterestRateCurveSettings({
            kinkUtilization1: 15,
            kinkUtilization2: 70,
            kinkRate1: 2,
            kinkRate2: 8,
            maxRateUnits: 255,
            feeRatePercent: 20,
            minFeeRate5BPS: 10,
            maxFeeRate25BPS: 160
        });

        CashGroupSettings memory cashGroupSettings = CashGroupSettings({
            maxMarketIndex: 3,
            rateOracleTimeWindow5Min: 72,
            maxDiscountFactor5BPS: 40,
            reserveFeeShare: 80,
            debtBuffer25BPS: 22,
            fCashHaircut25BPS: 22,
            minOracleRate25BPS: 20,
            liquidationfCashHaircut25BPS: 6,
            liquidationDebtBuffer25BPS: 6,
            maxOracleRate25BPS: 28
        });

        return CurrencySettings({
            primeDebtCurve: primeDebtCurve,
            primeCashOracle: oracle,
            cashGroupSettings: cashGroupSettings,
            rateOracleTimeWindow5Min: 72,
            allowPrimeDebt: true,
            underlyingName: "Dai Stablecoin",
            underlyingSymbol: "DAI",
            fCashCurves: fCashCurves,
            fCashDebts: new TotalfCashDebt[](0)
        });
    }

    function getUSDC(IPrimeCashHoldingsOracle oracle) internal pure returns (CurrencySettings memory) {
        InterestRateCurveSettings[] memory fCashCurves = new InterestRateCurveSettings[](3);
        fCashCurves[0] = InterestRateCurveSettings({
            kinkUtilization1: 15,
            kinkUtilization2: 70,
            kinkRate1: 17,
            kinkRate2: 51,
            maxRateUnits: 120,
            feeRatePercent: 8,
            minFeeRate5BPS: 3,
            maxFeeRate25BPS: 8
        });
        fCashCurves[1] = InterestRateCurveSettings({
            kinkUtilization1: 15,
            kinkUtilization2: 70,
            kinkRate1: 20,
            kinkRate2: 61,
            maxRateUnits: 100,
            feeRatePercent: 8,
            minFeeRate5BPS: 3,
            maxFeeRate25BPS: 8
        });
        fCashCurves[2] = InterestRateCurveSettings({
            kinkUtilization1: 15,
            kinkUtilization2: 60,
            kinkRate1: 20,
            kinkRate2: 55,
            maxRateUnits: 100,
            feeRatePercent: 8,
            minFeeRate5BPS: 3,
            maxFeeRate25BPS: 8
        });

        InterestRateCurveSettings memory primeDebtCurve = InterestRateCurveSettings({
            kinkUtilization1: 15,
            kinkUtilization2: 70,
            kinkRate1: 2,
            kinkRate2: 8,
            maxRateUnits: 255,
            feeRatePercent: 20,
            minFeeRate5BPS: 10,
            maxFeeRate25BPS: 160
        });

        CashGroupSettings memory cashGroupSettings = CashGroupSettings({
            maxMarketIndex: 3,
            rateOracleTimeWindow5Min: 72,
            maxDiscountFactor5BPS: 40,
            reserveFeeShare: 80,
            debtBuffer25BPS: 22,
            fCashHaircut25BPS: 22,
            minOracleRate25BPS: 20,
            liquidationfCashHaircut25BPS: 6,
            liquidationDebtBuffer25BPS: 6,
            maxOracleRate25BPS: 28
        });

        return CurrencySettings({
            primeDebtCurve: primeDebtCurve,
            primeCashOracle: oracle,
            cashGroupSettings: cashGroupSettings,
            rateOracleTimeWindow5Min: 72,
            allowPrimeDebt: true,
            underlyingName: "USD Coin",
            underlyingSymbol: "USDC",
            fCashCurves: fCashCurves,
            fCashDebts: new TotalfCashDebt[](0)
        });
    }

    function getWBTC(IPrimeCashHoldingsOracle oracle) internal pure returns (CurrencySettings memory) {
        InterestRateCurveSettings[] memory fCashCurves = new InterestRateCurveSettings[](2);
        fCashCurves[0] = InterestRateCurveSettings({
            kinkUtilization1: 15,
            kinkUtilization2: 70,
            kinkRate1: 17,
            kinkRate2: 40,
            maxRateUnits: 80,
            feeRatePercent: 8,
            minFeeRate5BPS: 3,
            maxFeeRate25BPS: 8
        });
        fCashCurves[1] = InterestRateCurveSettings({
            kinkUtilization1: 15,
            kinkUtilization2: 70,
            kinkRate1: 20,
            kinkRate2: 40,
            maxRateUnits: 80,
            feeRatePercent: 8,
            minFeeRate5BPS: 3,
            maxFeeRate25BPS: 8
        });

        InterestRateCurveSettings memory primeDebtCurve = InterestRateCurveSettings({
            kinkUtilization1: 15,
            kinkUtilization2: 70,
            kinkRate1: 2,
            kinkRate2: 8,
            maxRateUnits: 255,
            feeRatePercent: 20,
            minFeeRate5BPS: 10,
            maxFeeRate25BPS: 160
        });

        CashGroupSettings memory cashGroupSettings = CashGroupSettings({
            maxMarketIndex: 2,
            rateOracleTimeWindow5Min: 72,
            maxDiscountFactor5BPS: 40,
            reserveFeeShare: 80,
            debtBuffer25BPS: 22,
            fCashHaircut25BPS: 22,
            minOracleRate25BPS: 20,
            liquidationfCashHaircut25BPS: 6,
            liquidationDebtBuffer25BPS: 6,
            maxOracleRate25BPS: 28
        });

        return CurrencySettings({
            primeDebtCurve: primeDebtCurve,
            primeCashOracle: oracle,
            cashGroupSettings: cashGroupSettings,
            rateOracleTimeWindow5Min: 72,
            allowPrimeDebt: true,
            underlyingName: "Wrapped Bitcoin",
            underlyingSymbol: "WBTC",
            fCashCurves: fCashCurves,
            fCashDebts: new TotalfCashDebt[](0)
        });
    }

}