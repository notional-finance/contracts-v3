// SPDX-License-Identifier: BSUL-1.1
pragma solidity =0.7.6;
pragma abicoder v2;

import {
    BalanceState
} from "../../global/Types.sol";
import {Constants} from "../../global/Constants.sol";
import {SafeInt256} from "../../math/SafeInt256.sol";
import {SafeUint256} from "../../math/SafeUint256.sol";

import {TokenHandler} from "./TokenHandler.sol";
import {nTokenHandler} from "../nToken/nTokenHandler.sol";
import {nTokenSupply} from "../nToken/nTokenSupply.sol";

import {IRewarder} from "../../../interfaces/notional/IRewarder.sol";

library Incentives {
    using SafeUint256 for uint256;
    using SafeInt256 for int256;

    /// @notice Calculates the total incentives to claim including those claimed under the previous
    /// less accurate calculation. Once an account is migrated it will only claim incentives under
    /// the more accurate regime
    function calculateIncentivesToClaim(
        BalanceState memory balanceState,
        address tokenAddress,
        uint256 accumulatedNOTEPerNToken,
        uint256 finalNTokenBalance
    ) internal view returns (uint256 incentivesToClaim) {
        require(balanceState.lastClaimTime == 0);

        // If an account was migrated then they have no accountIncentivesDebt and should accumulate
        // incentives based on their share since the new regime calculation started.
        // If an account is just initiating their nToken balance then storedNTokenBalance will be zero
        // and they will have no incentives to claim.
        // This calculation uses storedNTokenBalance which is the balance of the account up until this point,
        // this is important to ensure that the account does not claim for nTokens that they will mint or
        // redeem on a going forward basis.

        // The calculation below has the following precision:
        //   storedNTokenBalance (INTERNAL_TOKEN_PRECISION)
        //   MUL accumulatedNOTEPerNToken (INCENTIVE_ACCUMULATION_PRECISION)
        //   DIV INCENTIVE_ACCUMULATION_PRECISION
        //  = INTERNAL_TOKEN_PRECISION - (accountIncentivesDebt) INTERNAL_TOKEN_PRECISION
        incentivesToClaim = incentivesToClaim.add(
            balanceState.storedNTokenBalance.toUint()
                .mul(accumulatedNOTEPerNToken)
                .div(Constants.INCENTIVE_ACCUMULATION_PRECISION)
                .sub(balanceState.accountIncentiveDebt)
        );

        // Update accountIncentivesDebt denominated in INTERNAL_TOKEN_PRECISION which marks the portion
        // of the accumulatedNOTE that the account no longer has a claim over. Use the finalNTokenBalance
        // here instead of storedNTokenBalance to mark the overall incentives claim that the account
        // does not have a claim over. We do not aggregate this value with the previous accountIncentiveDebt
        // because accumulatedNOTEPerNToken is already an aggregated value.

        // The calculation below has the following precision:
        //   finalNTokenBalance (INTERNAL_TOKEN_PRECISION)
        //   MUL accumulatedNOTEPerNToken (INCENTIVE_ACCUMULATION_PRECISION)
        //   DIV INCENTIVE_ACCUMULATION_PRECISION
        //   = INTERNAL_TOKEN_PRECISION
        balanceState.accountIncentiveDebt = finalNTokenBalance
            .mul(accumulatedNOTEPerNToken)
            .div(Constants.INCENTIVE_ACCUMULATION_PRECISION);
    }

    /// @notice Incentives must be claimed every time nToken balance changes.
    /// @dev BalanceState.accountIncentiveDebt is updated in place here
    function claimIncentives(
        BalanceState memory balanceState,
        address account,
        uint256 finalNTokenBalance
    ) internal returns (uint256 incentivesToClaim) {
        uint256 blockTime = block.timestamp;
        address tokenAddress = nTokenHandler.nTokenAddress(balanceState.currencyId);
        (uint256 priorNTokenSupply, /* */, /* */) = nTokenSupply.getStoredNTokenSupplyFactors(tokenAddress);
        // This will updated the nToken storage and return what the accumulatedNOTEPerNToken
        // is up until this current block time in 1e18 precision
        uint256 accumulatedNOTEPerNToken = nTokenSupply.changeNTokenSupply(
            tokenAddress,
            balanceState.netNTokenSupplyChange,
            blockTime
        );

        incentivesToClaim = calculateIncentivesToClaim(
            balanceState,
            tokenAddress,
            accumulatedNOTEPerNToken,
            finalNTokenBalance
        );

        // If a secondary incentive rewarder is set, then call it
        IRewarder rewarder = nTokenHandler.getSecondaryRewarder(tokenAddress);
        if (address(rewarder) != address(0)) {
            rewarder.claimRewards(
                account,
                balanceState.currencyId,
                // When this method is called from finalize, the storedNTokenBalance has not
                // been updated to finalNTokenBalance yet so this is the balance before the change.
                balanceState.storedNTokenBalance.toUint(),
                finalNTokenBalance,
                priorNTokenSupply
            );
        }

        if (incentivesToClaim > 0) TokenHandler.transferIncentive(account, incentivesToClaim);
    }
}
