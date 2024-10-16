// SPDX-License-Identifier: BSUL-1.1
pragma solidity =0.7.6;
pragma abicoder v2;

import {
    PrimeRate,
    nTokenPortfolio,
    CashGroupParameters,
    MarketParameters,
    PortfolioAsset
} from "../../global/Types.sol";
import {Constants} from "../../global/Constants.sol";
import {SafeInt256} from "../../math/SafeInt256.sol";
import {Bitmap} from "../../math/Bitmap.sol";

import {BitmapAssetsHandler} from "../portfolio/BitmapAssetsHandler.sol";
import {PrimeRateLib} from "../pCash/PrimeRateLib.sol";
import {CashGroup} from "../markets/CashGroup.sol";
import {DateTime} from "../markets/DateTime.sol";
import {AssetHandler} from "../valuation/AssetHandler.sol";

import {nTokenHandler} from "./nTokenHandler.sol";

library nTokenCalculations {
    using Bitmap for bytes32;
    using SafeInt256 for int256;
    using PrimeRateLib for PrimeRate;
    using CashGroup for CashGroupParameters;

    /// @notice Calculates the tokens to mint to the account as a ratio of the nToken
    /// present value denominated in asset cash terms.
    /// @return the amount of tokens to mint, the ifCash bitmap
    function calculateTokensToMint(
        nTokenPortfolio memory nToken,
        int256 primeCashToDeposit,
        uint256 blockTime
    ) internal view returns (int256) {
        require(primeCashToDeposit >= 0); // dev: deposit amount negative
        if (primeCashToDeposit == 0) return 0;

        if (nToken.lastInitializedTime != 0) {
            // For the sake of simplicity, nTokens cannot be minted if they have assets
            // that need to be settled. This is only done during market initialization.
            uint256 nextSettleTime = nTokenHandler.getNextSettleTime(nToken);
            // If next settle time <= blockTime then the token can be settled
            require(nextSettleTime > blockTime, "Requires settlement");
        }

        if (nToken.totalSupply == 0) {
            // Allow for the first deposit and bypass all the PV valuation
            return primeCashToDeposit;
        } else {
            (int256 nTokenOracleValue, int256 nTokenSpotValue) = nTokenCalculations.getNTokenPrimePVForMinting(
                nToken, blockTime
            );

            // Defensive check to ensure PV remains positive
            require(nTokenOracleValue >= 0);
            require(nTokenSpotValue >= 0);

            int256 maxValueDeviationRP = int256(
                uint256(uint8(nToken.parameters[Constants.MAX_MINT_DEVIATION_LIMIT])) * Constants.FIVE_BASIS_POINTS
            );
            // Check deviation limit here
            int256 deviationInRP = nTokenOracleValue.sub(nTokenSpotValue).abs()
                .divInRatePrecision(nTokenOracleValue);
            require(deviationInRP <= maxValueDeviationRP, "Over Deviation Limit");

            // Use the larger PV when minting nTokens to ensure that the minting is at the lower price
            // of the two values.
            int256 nTokenValueForMinting = SafeInt256.max(nTokenOracleValue, nTokenSpotValue);

            // nTokenSpotValuePost = nTokenOracleValue + amountToDeposit
            // (tokenSupply + tokensToMint) / tokenSupply == (nTokenSpotValue + amountToDeposit) / nTokenOracleValue
            // (tokenSupply + tokensToMint) == (nTokenSpotValue + amountToDeposit) * tokenSupply / nTokenOracleValue
            // (tokenSupply + tokensToMint) == tokenSupply + (amountToDeposit * tokenSupply) / nTokenSpotValue
            // tokensToMint == (amountToDeposit * tokenSupply) / nTokenSpotValue
            return primeCashToDeposit.mul(nToken.totalSupply).div(nTokenValueForMinting);
        }
    }

    function getNTokenPrimePVForMinting(nTokenPortfolio memory nToken, uint256 blockTime)
        internal view returns (int256 nTokenOracleValue, int256 nTokenSpotValue) {
        // Skip the "nextSettleTime" check in this method. nTokens are not mintable when markets
        // are not yet initialized.

        (int256 totalOracleValueInMarkets, /* int256[] memory netfCash */) = getNTokenMarketValue(
            {nToken: nToken, blockTime: blockTime, useOracleRate: true}
        );
        (int256 totalSpotValueInMarkets, /* int256[] memory netfCash */) = getNTokenMarketValue(
            {nToken: nToken, blockTime: blockTime, useOracleRate: false}
        );
        int256 ifCashResidualPrimePV = _getIfCashResidualPrimePV(nToken, blockTime);

        // Return the total present value denominated in asset terms
        nTokenOracleValue = totalOracleValueInMarkets.add(ifCashResidualPrimePV).add(nToken.cashBalance);
        nTokenSpotValue = totalSpotValueInMarkets.add(ifCashResidualPrimePV).add(nToken.cashBalance);
    }

    /// @notice Returns the nToken present value denominated in asset terms.
    function getNTokenPrimePV(nTokenPortfolio memory nToken, uint256 blockTime)
        internal view returns (int256) {
        {
            uint256 nextSettleTime = nTokenHandler.getNextSettleTime(nToken);
            // If the first asset maturity has passed (the 3 month), this means that all the LTs must
            // be settled except the 6 month (which is now the 3 month). We don't settle LTs except in
            // initialize markets so we calculate the cash value of the portfolio here.
            if (nextSettleTime <= blockTime) {
                // NOTE: this condition should only be present for a very short amount of time, which is the window between
                // when the markets are no longer tradable at quarter end and when the new markets have been initialized.
                // We time travel back to one second before maturity to value the liquidity tokens. Although this value is
                // not strictly correct the different should be quite slight. We do this to ensure that free collateral checks
                // for withdraws and liquidations can still be processed. If this condition persists for a long period of time then
                // the entire protocol will have serious problems as markets will not be tradable.
                blockTime = nextSettleTime - 1;
            }
        }

        // This is the total value in liquid assets
        (int256 totalOracleValueInMarkets, /* int256[] memory netfCash */) = getNTokenMarketValue(
            {nToken: nToken, blockTime: blockTime, useOracleRate: true}
        );

        int256 ifCashResidualPrimePV = _getIfCashResidualPrimePV(nToken, blockTime);

        // Return the total present value denominated in prime cash terms
        return totalOracleValueInMarkets.add(ifCashResidualPrimePV).add(nToken.cashBalance);
    }

    function _getIfCashResidualPrimePV(
        nTokenPortfolio memory nToken, uint256 blockTime
    ) private view returns (int256) {
        // Then get the total value in any idiosyncratic fCash residuals (if they exist)
        bytes32 ifCashBits = getNTokenifCashBits(
            nToken.tokenAddress,
            nToken.cashGroup.currencyId,
            nToken.lastInitializedTime,
            blockTime,
            nToken.cashGroup.maxMarketIndex
        );

        if (ifCashBits != 0) {
            // Non idiosyncratic residuals have already been accounted for
            (int256 ifCashResidualUnderlyingPV, /* hasDebt */) = BitmapAssetsHandler.getNetPresentValueFromBitmap(
                nToken.tokenAddress,
                nToken.cashGroup.currencyId,
                nToken.lastInitializedTime,
                blockTime,
                nToken.cashGroup,
                false, // nToken present value calculation does not use risk adjusted values
                ifCashBits
            );
            return nToken.cashGroup.primeRate.convertFromUnderlying(ifCashResidualUnderlyingPV);
        } else {
            return 0;
        }
    }

    /**
     * @notice Handles the case when liquidity tokens should be withdrawn in proportion to their amounts
     * in the market. This will be the case when there is no idiosyncratic fCash residuals in the nToken
     * portfolio.
     * @param nToken portfolio object for nToken
     * @param nTokensToRedeem amount of nTokens to redeem
     * @param tokensToWithdraw array of liquidity tokens to withdraw from each market, proportional to
     * the account's share of the total supply
     * @param netfCash an empty array to hold net fCash values calculated later when the tokens are actually
     * withdrawn from markets
     */
    function _getProportionalLiquidityTokens(
        nTokenPortfolio memory nToken,
        int256 nTokensToRedeem
    ) private pure returns (int256[] memory tokensToWithdraw, int256[] memory netfCash) {
        uint256 numMarkets = nToken.portfolioState.storedAssets.length;
        tokensToWithdraw = new int256[](numMarkets);
        netfCash = new int256[](numMarkets);

        for (uint256 i = 0; i < numMarkets; i++) {
            int256 totalTokens = nToken.portfolioState.storedAssets[i].notional;
            tokensToWithdraw[i] = totalTokens.mul(nTokensToRedeem).div(nToken.totalSupply);
        }
    }

    /**
     * @notice Returns the number of liquidity tokens to withdraw from each market if the nToken
     * has idiosyncratic residuals during nToken redeem. In this case the redeemer will take
     * their cash from the rest of the fCash markets, redeeming around the nToken.
     * @param nToken portfolio object for nToken
     * @param nTokensToRedeem amount of nTokens to redeem
     * @param blockTime block time
     * @param ifCashBits the bits in the bitmap that represent ifCash assets
     * @return tokensToWithdraw array of tokens to withdraw from each corresponding market
     * @return netfCash array of netfCash amounts to go back to the account
     */
    function getLiquidityTokenWithdraw(
        nTokenPortfolio memory nToken,
        int256 nTokensToRedeem,
        uint256 blockTime,
        bytes32 ifCashBits
    ) internal view returns (int256[] memory, int256[] memory) {
        // If there are no ifCash bits set then this will just return the proportion of all liquidity tokens
        if (ifCashBits == 0) return _getProportionalLiquidityTokens(nToken, nTokensToRedeem);

        (
            int256 totalPrimeValueInMarkets,
            int256[] memory netfCash
        // Need to use market values here to match the withdraw amounts on minting
        ) = getNTokenMarketValue({nToken: nToken, blockTime: blockTime, useOracleRate: false});
        int256[] memory tokensToWithdraw = new int256[](netfCash.length);

        // NOTE: this total portfolio asset value does not include any cash balance the nToken may hold.
        // The redeemer will always get a proportional share of this cash balance and therefore we don't
        // need to account for it here when we calculate the share of liquidity tokens to withdraw. We are
        // only concerned with the nToken's portfolio assets in this method.
        int256 totalPortfolioAssetValue;
        {
            // Returns the risk adjusted net present value for the idiosyncratic residuals
            (int256 underlyingPV, /* hasDebt */) = BitmapAssetsHandler.getNetPresentValueFromBitmap(
                nToken.tokenAddress,
                nToken.cashGroup.currencyId,
                nToken.lastInitializedTime,
                blockTime,
                nToken.cashGroup,
                true, // use risk adjusted here to assess a penalty for withdrawing around the residual
                ifCashBits
            );

            // NOTE: we do not include cash balance here because the account will always take their share
            // of the cash balance regardless of the residuals
            totalPortfolioAssetValue = totalPrimeValueInMarkets.add(
                nToken.cashGroup.primeRate.convertFromUnderlying(underlyingPV)
            );
        }

        // Loops through each liquidity token and calculates how much the redeemer can withdraw to get
        // the requisite amount of present value after adjusting for the ifCash residual value that is
        // not accessible via redemption.
        for (uint256 i = 0; i < tokensToWithdraw.length; i++) {
            int256 totalTokens = nToken.portfolioState.storedAssets[i].notional;
            // Redeemer's baseline share of the liquidity tokens based on total supply:
            //      redeemerShare = totalTokens * nTokensToRedeem / totalSupply
            // Scalar factor to account for residual value (need to inflate the tokens to withdraw
            // proportional to the value locked up in ifCash residuals):
            //      scaleFactor = totalPortfolioAssetValue / totalPrimeValueInMarkets
            // Final math equals:
            //      tokensToWithdraw = redeemerShare * scalarFactor
            //      tokensToWithdraw = (totalTokens * nTokensToRedeem * totalPortfolioAssetValue)
            //         / (totalPrimeValueInMarkets * totalSupply)
            tokensToWithdraw[i] = totalTokens
                .mul(nTokensToRedeem)
                .mul(totalPortfolioAssetValue);

            tokensToWithdraw[i] = tokensToWithdraw[i]
                .div(totalPrimeValueInMarkets)
                .div(nToken.totalSupply);

            // This is the share of net fcash that will be credited back to the account
            netfCash[i] = netfCash[i].mul(tokensToWithdraw[i]).div(totalTokens);
        }

        return (tokensToWithdraw, netfCash);
    }

    /// @notice Returns the value of all the liquid assets in an nToken portfolio which are defined by
    /// the liquidity tokens held in each market and their corresponding fCash positions. The formula
    /// can be described as:
    /// totalPrimeValue = sum_per_liquidity_token(cashClaim + presentValue(netfCash))
    ///     where netfCash = fCashClaim + fCash
    ///     and fCash refers the the fCash position at the corresponding maturity
    function getNTokenMarketValue(nTokenPortfolio memory nToken, uint256 blockTime, bool useOracleRate)
        internal view returns (int256 totalPrimeValue, int256[] memory netfCash)
    {
        uint256 numMarkets = nToken.portfolioState.storedAssets.length;
        netfCash = new int256[](numMarkets);

        MarketParameters memory market;
        for (uint256 i = 0; i < numMarkets; i++) {
            // Load the corresponding market into memory
            nToken.cashGroup.loadMarket(market, i + 1, true, blockTime);
            PortfolioAsset memory liquidityToken = nToken.portfolioState.storedAssets[i];

            // Get the fCash claims and fCash assets. We do not use haircut versions here because
            // nTokenRedeem does not require it and getNTokenPV does not use it (a haircut is applied
            // at the end of the calculation to the entire PV instead).
            (int256 primeCashClaim, int256 fCashClaim) = AssetHandler.getCashClaims(liquidityToken, market);

            // fCash is denominated in underlying
            netfCash[i] = fCashClaim.add(
                BitmapAssetsHandler.getifCashNotional(
                    nToken.tokenAddress,
                    nToken.cashGroup.currencyId,
                    liquidityToken.maturity
                )
            );

            // This calculates for a single liquidity token:
            // primeCashClaim + convertToPrimeCash(pv(netfCash))
            int256 netPrimeValueInMarket = primeCashClaim.add(
                nToken.cashGroup.primeRate.convertFromUnderlying(
                    AssetHandler.getPresentfCashValue(
                        netfCash[i],
                        liquidityToken.maturity,
                        blockTime,
                        // No need to call cash group for oracle rate, it is up to date here
                        // and we are assured to be referring to this market.
                        useOracleRate ? market.oracleRate : market.lastImpliedRate
                    )
                )
            );

            // Calculate the running total
            totalPrimeValue = totalPrimeValue.add(netPrimeValueInMarket);
        }
    }

    /// @notice Returns just the bits in a bitmap that are idiosyncratic
    function getNTokenifCashBits(
        address tokenAddress,
        uint256 currencyId,
        uint256 lastInitializedTime,
        uint256 blockTime,
        uint256 maxMarketIndex
    ) internal view returns (bytes32) {
        // If max market index is less than or equal to 2, there are never ifCash assets by construction
        if (maxMarketIndex <= 2) return bytes32(0);
        bytes32 assetsBitmap = BitmapAssetsHandler.getAssetsBitmap(tokenAddress, currencyId);
        // Handles the case when there are no assets at the first initialization
        if (assetsBitmap == 0) return assetsBitmap;

        uint256 tRef = DateTime.getReferenceTime(blockTime);

        if (tRef == lastInitializedTime) {
            // This is a more efficient way to turn off ifCash assets in the common case when the market is
            // initialized immediately
            return assetsBitmap & ~(Constants.ACTIVE_MARKETS_MASK);
        } else {
            // In this branch, initialize markets has occurred past the time above. It would occur in these
            // two scenarios (both should be exceedingly rare):
            // 1. initializing a cash group with 3+ markets for the first time (not beginning on the tRef)
            // 2. somehow initialize markets has been delayed for more than 24 hours
            for (uint i = 1; i <= maxMarketIndex; i++) {
                // In this loop we get the maturity of each active market and turn off the corresponding bit
                // one by one. It is less efficient than the option above.
                uint256 maturity = tRef + DateTime.getTradedMarket(i);
                (uint256 bitNum, /* */) = DateTime.getBitNumFromMaturity(lastInitializedTime, maturity);
                assetsBitmap = assetsBitmap.setBit(bitNum, false);
            }

            return assetsBitmap;
        }
    }
}