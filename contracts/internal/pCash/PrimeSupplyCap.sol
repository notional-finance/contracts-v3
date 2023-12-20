// SPDX-License-Identifier: BSUL-1.1
pragma solidity =0.7.6;
pragma abicoder v2;

import {PrimeRate, PrimeCashFactorsStorage} from "../../global/Types.sol";
import {LibStorage} from "../../global/LibStorage.sol";
import {Constants} from "../../global/Constants.sol";
import {PrimeRateLib} from "./PrimeRateLib.sol";

import {FloatingPoint} from "../../math/FloatingPoint.sol";
import {SafeUint256} from "../../math/SafeUint256.sol";
import {SafeInt256} from "../../math/SafeInt256.sol";

library PrimeSupplyCap {
    using PrimeRateLib for PrimeRate;
    using SafeUint256 for uint256;
    using SafeInt256 for int256;

    /// @notice Checks whether or not a currency has exceeded its total prime supply cap. Used to
    /// prevent some listed currencies to be used as collateral above a threshold where liquidations
    /// can be safely done on chain.
    /// @dev Called during deposits in AccountAction and BatchAction. Supply caps are not checked
    /// during settlement, liquidation and withdraws.
    function checkSupplyCap(PrimeRate memory pr, uint16 currencyId) internal view {
        (
            uint256 maxUnderlyingSupply,
            uint256 totalUnderlyingSupply,
            /* */, /* */
        ) = getSupplyCap(pr, currencyId);
        if (maxUnderlyingSupply == 0) return;

        require(totalUnderlyingSupply <= maxUnderlyingSupply, "Over Supply Cap");
    }

    function checkDebtCap(PrimeRate memory pr, uint16 currencyId) internal view {
        (
            /* */, /* */,
            uint256 maxUnderlyingDebt,
            uint256 totalUnderlyingDebt
        ) = getSupplyCap(pr, currencyId);
        if (maxUnderlyingDebt == 0) return;

        require(totalUnderlyingDebt <= maxUnderlyingDebt, "Over Debt Cap");
    }

    function getSupplyCap(PrimeRate memory pr, uint16 currencyId) internal view returns (
        uint256 maxUnderlyingSupply,
        uint256 totalUnderlyingSupply,
        uint256 maxUnderlyingDebt,
        uint256 totalUnderlyingDebt
    ) {
        PrimeCashFactorsStorage storage s = LibStorage.getPrimeCashFactors()[currencyId];
        maxUnderlyingSupply = FloatingPoint.unpackFromBits(s.maxUnderlyingSupply);

        // If maxUnderlyingSupply or maxPrimeDebtUtilization is set to zero, there is no debt cap. The
        // debt cap is applied to prevent the supply cap from being locked up by extremely high utilization
        maxUnderlyingDebt = maxUnderlyingSupply
            .mul(s.maxPrimeDebtUtilization).div(uint256(Constants.PERCENTAGE_DECIMALS));

        // No potential for overflow due to storage size
        int256 totalPrimeSupply = int256(uint256(s.totalPrimeSupply));
        totalUnderlyingSupply = pr.convertToUnderlying(totalPrimeSupply).toUint();

        // totalPrimeDebt is stored as a uint88 so the negation here will never underflow
        int256 totalPrimeDebt = -int256(uint256(s.totalPrimeDebt));
        totalUnderlyingDebt = pr.convertDebtStorageToUnderlying(totalPrimeDebt).neg().toUint();
    }
}