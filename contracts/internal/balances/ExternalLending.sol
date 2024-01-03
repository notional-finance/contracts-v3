// SPDX-License-Identifier: BSUL-1.1
pragma solidity =0.7.6;
pragma abicoder v2;

import {
    Token,
    PrimeRate,
    PrimeCashFactors,
    RebalancingTargetData
} from "../../global/Types.sol";
import {
    IPrimeCashHoldingsOracle,
    OracleData,
    RedeemData,
    DepositData
} from "../../../interfaces/notional/IPrimeCashHoldingsOracle.sol";
import {TokenHandler} from "./TokenHandler.sol";

import {LibStorage} from "../../global/LibStorage.sol";
import {SafeInt256} from "../../math/SafeInt256.sol";
import {SafeUint256} from "../../math/SafeUint256.sol";
import {Constants} from "../../global/Constants.sol";
import {IERC20} from "../../../interfaces/IERC20.sol";

import {PrimeRateLib} from "../pCash/PrimeRateLib.sol";
import {PrimeCashExchangeRate} from "../pCash/PrimeCashExchangeRate.sol";
import {GenericToken} from "./protocols/GenericToken.sol";


library ExternalLending {
    using PrimeRateLib for PrimeRate;
    using SafeUint256 for uint256;
    using SafeInt256 for int256;
    using TokenHandler for Token;

    function getTargetExternalLendingAmount(
        Token memory underlyingToken,
        PrimeCashFactors memory factors,
        RebalancingTargetData memory rebalancingTargetData,
        OracleData memory oracleData,
        PrimeRate memory pr
    ) internal pure returns (uint256 targetAmount) {
        // Short circuit a zero target
        if (rebalancingTargetData.targetUtilization == 0) return 0;

        int256 totalPrimeCashInUnderlying = pr.convertToUnderlying(int256(factors.totalPrimeSupply));
        int256 totalPrimeDebtInUnderlying = pr.convertDebtStorageToUnderlying(int256(factors.totalPrimeDebt).neg()).abs();

        // The target amount to lend is based on a target "utilization" of the total prime supply. For example, for
        // a target utilization of 80%, if the prime cash utilization is 70% (totalPrimeSupply / totalPrimeDebt) then
        // we want to lend 10% of the total prime supply. This ensures that 20% of the totalPrimeSupply will not be held
        // in external money markets which run the risk of becoming unredeemable.
        int256 targetExternalUnderlyingLend = totalPrimeCashInUnderlying
            .mul(rebalancingTargetData.targetUtilization)
            .div(Constants.PERCENTAGE_DECIMALS)
            .sub(totalPrimeDebtInUnderlying);
        // Floor this value at zero. This will be negative above the target utilization. We do not want to be lending at
        // all above the target.
        if (targetExternalUnderlyingLend < 0) targetExternalUnderlyingLend = 0;

        // To ensure redeemability of Notional’s funds on external lending markets,
        // Notional requires there to be redeemable funds on the external lending market
        // that are a multiple of the funds that Notional has lent on that market itself.
        //
        // The max amount that Notional can lend on that market is a function
        // of the excess redeemable funds on that market
        // (funds that are redeemable in excess of Notional’s own funds on that market)
        // and the externalWithdrawThreshold.
        //
        // excessFunds = externalUnderlyingAvailableForWithdraw - currentExternalUnderlyingLend
        //
        // maxExternalUnderlyingLend * (externalWithdrawThreshold + 1) = maxExternalUnderlyingLend + excessFunds
        //
        // maxExternalUnderlyingLend * (externalWithdrawThreshold + 1) - maxExternalUnderlyingLend = excessFunds
        //
        // maxExternalUnderlyingLend * externalWithdrawThreshold = excessFunds
        //
        // maxExternalUnderlyingLend = excessFunds / externalWithdrawThreshold
        uint256 maxExternalUnderlyingLend;
        if (oracleData.currentExternalUnderlyingLend < oracleData.externalUnderlyingAvailableForWithdraw) {
            maxExternalUnderlyingLend =
                (oracleData.externalUnderlyingAvailableForWithdraw - oracleData.currentExternalUnderlyingLend)
                .mul(uint256(Constants.PERCENTAGE_DECIMALS))
                .div(rebalancingTargetData.externalWithdrawThreshold);
        } else {
            maxExternalUnderlyingLend = 0;
        }

        targetAmount = SafeUint256.min(
            // totalPrimeCashInUnderlying and totalPrimeDebtInUnderlying are in 8 decimals, convert it to native
            // token precision here for accurate comparison. No underflow possible since targetExternalUnderlyingLend
            // is floored at zero.
            uint256(underlyingToken.convertToExternal(targetExternalUnderlyingLend)),
            // maxExternalUnderlyingLend is limit enforced by setting externalWithdrawThreshold
            // maxExternalDeposit is limit due to the supply cap on external pools
            SafeUint256.min(maxExternalUnderlyingLend, oracleData.maxExternalDeposit)
        );
        // in case of redemption, make sure there is enough to withdraw, important for health check so that
        // it does not trigger rebalances (redemptions) when there is nothing to redeem
        if (targetAmount < oracleData.currentExternalUnderlyingLend) {
            uint256 forRedemption = oracleData.currentExternalUnderlyingLend - targetAmount;
            if (oracleData.externalUnderlyingAvailableForWithdraw < forRedemption) {
                // increase target amount so that redemptions amount match externalUnderlyingAvailableForWithdraw
                targetAmount = targetAmount.add(
                    // unchecked - is safe here, overflow is not possible due to above if conditional
                    forRedemption - oracleData.externalUnderlyingAvailableForWithdraw
                );
            }
        }
    }

    /// @notice Prime cash holdings may be in underlying tokens or they may be held in other money market
    /// protocols like Compound, Aave or Euler. If there is insufficient underlying tokens to withdraw on
    /// the contract, this method will redeem money market tokens in order to gain sufficient underlying
    /// to withdraw from the contract.
    /// @param currencyId associated currency id
    /// @param underlying underlying token information
    /// @param withdrawAmountExternal amount of underlying to withdraw in external token precision
    function redeemMoneyMarketIfRequired(
        uint16 currencyId,
        Token memory underlying,
        uint256 withdrawAmountExternal
    ) internal {
        // If there is sufficient balance of the underlying to withdraw from the contract
        // immediately, just return.
        mapping(address => uint256) storage store = LibStorage.getStoredTokenBalances();
        uint256 currentBalance = store[underlying.tokenAddress];
        if (withdrawAmountExternal <= currentBalance) return;

        IPrimeCashHoldingsOracle oracle = PrimeCashExchangeRate.getPrimeCashHoldingsOracle(currencyId);
        // Redemption data returns an array of contract calls to make from the Notional proxy (which
        // is holding all of the money market tokens).
        (RedeemData[] memory data) = oracle.getRedemptionCalldata(withdrawAmountExternal - currentBalance);

        // This is the total expected underlying that we should redeem after all redemption calls
        // are executed.
        uint256 totalUnderlyingRedeemed = executeMoneyMarketRedemptions(underlying, data);

        // Ensure that we have sufficient funds before we exit
        require(withdrawAmountExternal <= currentBalance.add(totalUnderlyingRedeemed)); // dev: insufficient redeem
    }

    /// @notice It is critical that this method measures and records the balanceOf changes before and after
    /// every token change. If not, then external donations can affect the valuation of pCash and pDebt
    /// tokens which may be exploitable.
    /// @param redeemData parameters from the prime cash holding oracle
    function executeMoneyMarketRedemptions(
        Token memory underlyingToken,
        RedeemData[] memory redeemData
    ) internal returns (uint256 totalUnderlyingRedeemed) {
        for (uint256 i; i < redeemData.length; i++) {
            RedeemData memory data = redeemData[i];
            // Measure the token balance change if the `assetToken` value is set in the
            // current redemption data struct. 
            uint256 oldAssetBalance = IERC20(data.assetToken).balanceOf(address(this));

            // Measure the underlying balance change before and after the call.
            uint256 oldUnderlyingBalance = TokenHandler.balanceOf(underlyingToken, address(this));

            // Some asset tokens may require multiple calls to redeem if there is an unstake
            // or redemption from WETH involved. We only measure the asset token balance change
            // on the final redemption call, as dictated by the prime cash holdings oracle.
            for (uint256 j; j < data.targets.length; j++) {
                GenericToken.executeLowLevelCall(data.targets[j], 0, data.callData[j]);
            }

            // Ensure that we get sufficient underlying on every redemption
            uint256 newUnderlyingBalance = TokenHandler.balanceOf(underlyingToken, address(this));
            uint256 underlyingBalanceChange = newUnderlyingBalance.sub(oldUnderlyingBalance);
            // If the call is not the final redemption, then expectedUnderlying should
            // be set to zero.
            require(data.expectedUnderlying <= underlyingBalanceChange);

            // Measure and update the asset token
            uint256 newAssetBalance = IERC20(data.assetToken).balanceOf(address(this));
            require(newAssetBalance <= oldAssetBalance);

            if (
                (data.rebasingTokenBalanceAdjustment != 0) &&
                // This equation only makes sense when the "asset token" is a rebasing token
                // in the same denomination as the underlying token. This will only be reached
                // if the rebasingTokenBalanceAdjustment is set to a non-zero value
                (underlyingBalanceChange != oldAssetBalance.sub(newAssetBalance))
            ) {
                newAssetBalance = newAssetBalance.add(data.rebasingTokenBalanceAdjustment);
            }

            TokenHandler.updateStoredTokenBalance(data.assetToken, oldAssetBalance, newAssetBalance);

            // Update the total value with the net change
            totalUnderlyingRedeemed = totalUnderlyingRedeemed.add(underlyingBalanceChange);

            // totalUnderlyingRedeemed is always positive or zero.
            TokenHandler.updateStoredTokenBalance(underlyingToken.tokenAddress, oldUnderlyingBalance, newUnderlyingBalance);
        }
    }

    /// @notice Executes deposits to an external lending protocol. Only called during a rebalance executed
    /// by the TreasuryAction contract.
    function executeDeposits(Token memory underlyingToken, DepositData[] memory deposits) internal {
        for (uint256 i; i < deposits.length; i++) {
            DepositData memory depositData = deposits[i];
            // Measure the token balance change if the `assetToken` value is set in the
            // current deposit data struct.
            uint256 oldAssetBalance = IERC20(depositData.assetToken).balanceOf(address(this));

            // Measure the underlying balance change before and after the call.
            uint256 oldUnderlyingBalance = underlyingToken.balanceOf(address(this));

            for (uint256 j; j < depositData.targets.length; ++j) {
                GenericToken.executeLowLevelCall(
                    depositData.targets[j],
                    depositData.msgValue[j],
                    depositData.callData[j]
                );
            }

            // Ensure that the underlying balance change matches the deposit amount
            uint256 newUnderlyingBalance = underlyingToken.balanceOf(address(this));
            uint256 underlyingBalanceChange = oldUnderlyingBalance.sub(newUnderlyingBalance);
            // Ensure that only the specified amount of underlying has left the protocol
            require(underlyingBalanceChange <= depositData.underlyingDepositAmount);

            // Measure and update the asset token
            uint256 newAssetBalance = IERC20(depositData.assetToken).balanceOf(address(this));
            require(oldAssetBalance <= newAssetBalance);

            if (
                (depositData.rebasingTokenBalanceAdjustment != 0) &&
                // This equation only makes sense when the "asset token" is a rebasing token
                // in the same denomination as the underlying token. This will only be reached
                // if the rebasingTokenBalanceAdjustment is set to a non-zero value
                (underlyingBalanceChange != newAssetBalance.sub(oldAssetBalance))
            ) {
                newAssetBalance = newAssetBalance.add(depositData.rebasingTokenBalanceAdjustment);
            }

            TokenHandler.updateStoredTokenBalance(depositData.assetToken, oldAssetBalance, newAssetBalance);
            TokenHandler.updateStoredTokenBalance(
                underlyingToken.tokenAddress, oldUnderlyingBalance, newUnderlyingBalance
            );
        }
    }

}
