// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.7.0;
pragma abicoder v2;

import "../valuation/AssetHandler.sol";
import "../markets/Market.sol";
import "../markets/AssetRate.sol";
import "../portfolio/PortfolioHandler.sol";
import "../../math/SafeInt256.sol";
import "../../global/Constants.sol";
import "../../global/Types.sol";

library SettlePortfolioAssets {
    using SafeInt256 for int256;
    using AssetRate for AssetRateParameters;
    using PortfolioHandler for PortfolioState;
    using AssetHandler for PortfolioAsset;

    /// @dev Returns a SettleAmount array for the assets that will be settled
    function _getSettleAmountArray(PortfolioState memory portfolioState, uint256 blockTime)
        private
        pure
        returns (SettleAmount[] memory)
    {
        uint256 currenciesSettled;
        uint256 lastCurrencyId = 0;
        if (portfolioState.storedAssets.length == 0) return new SettleAmount[](0);

        // Loop backwards so "lastCurrencyId" will be set to the first currency in the portfolio
        // NOTE: if this contract is ever upgraded to Solidity 0.8+ then this i-- will underflow and cause
        // a revert, must wrap in an unchecked.
        for (uint256 i = portfolioState.storedAssets.length; (i--) > 0;) {
            PortfolioAsset memory asset = portfolioState.storedAssets[i];
            // @audit-ok assets settle on exactly blocktime
            if (asset.getSettlementDate() > blockTime) {
                continue;
            }

            // Assume that this is sorted by cash group and maturity, currencyId = 0 is unused so this
            // will work for the first asset
            // @audit-ok
            if (lastCurrencyId != asset.currencyId) {
                lastCurrencyId = asset.currencyId;
                currenciesSettled++;
            }
        }

        // Actual currency ids will be set as we loop through the portfolio and settle assets
        SettleAmount[] memory settleAmounts = new SettleAmount[](currenciesSettled);
        // @audit-ok
        if (currenciesSettled > 0) settleAmounts[0].currencyId = lastCurrencyId;
        return settleAmounts;
    }

    /// @notice Shared calculation for liquidity token settlement
    function _calculateMarketStorage(PortfolioAsset memory asset)
        private
        view
        returns (
            int256,
            int256,
            SettlementMarket memory
        )
    {
        // @audit just have the market object settle the positions and return the net amounts
        // @audit this is the same as removing liquidity from a market, don't duplicate that method
        SettlementMarket memory market =
            Market.getSettlementMarket(asset.currencyId, asset.maturity, asset.getSettlementDate());

        int256 assetCash = market.totalAssetCash.mul(asset.notional).div(market.totalLiquidity);
        int256 fCash = market.totalfCash.mul(asset.notional).div(market.totalLiquidity);

        market.totalfCash = market.totalfCash.subNoNeg(fCash);
        market.totalAssetCash = market.totalAssetCash.subNoNeg(assetCash);
        market.totalLiquidity = market.totalLiquidity.subNoNeg(asset.notional);

        return (assetCash, fCash, market);
    }

    /// @notice Settles a liquidity token which requires getting the claims on both cash and fCash,
    /// converting the fCash portion to cash at the settlement rate.
    function _settleLiquidityToken(
        PortfolioAsset memory asset,
        AssetRateParameters memory settlementRate
    ) private view returns (int256, SettlementMarket memory) {
        (int256 assetCash, int256 fCash, SettlementMarket memory market) =
            _calculateMarketStorage(asset);

        // @audit-ok correct settlement rate
        assetCash = assetCash.add(settlementRate.convertFromUnderlying(fCash));
        return (assetCash, market);
    }

    /// @notice Settles a liquidity token to idiosyncratic fCash, this occurs when the maturity is still in the future
    function _settleLiquidityTokenTofCash(PortfolioState memory portfolioState, uint256 index)
        private
        view
        returns (int256, SettlementMarket memory)
    {
        PortfolioAsset memory liquidityToken = portfolioState.storedAssets[index];
        (int256 assetCash, int256 fCash, SettlementMarket memory market) =
            _calculateMarketStorage(liquidityToken);

        // If the liquidity token's maturity is still in the future then we change the entry to be
        // an idiosyncratic fCash entry with the net fCash amount.
        if (index != 0) {
            // Check to see if the previous index is the matching fCash asset, this will be the case when the
            // portfolio is sorted
            PortfolioAsset memory fCashAsset = portfolioState.storedAssets[index - 1];

            if (
                fCashAsset.currencyId == liquidityToken.currencyId &&
                fCashAsset.maturity == liquidityToken.maturity &&
                fCashAsset.assetType == Constants.FCASH_ASSET_TYPE
            ) {
                // @audit-ok
                // This fCash asset has not matured if were are settling to fCash
                fCashAsset.notional = fCashAsset.notional.add(fCash);
                fCashAsset.storageState = AssetStorageState.Update;

                portfolioState.deleteAsset(index);
                return (assetCash, market);
            }
        }

        // @audit-ok we are going to delete this asset anyway
        liquidityToken.assetType = Constants.FCASH_ASSET_TYPE;
        liquidityToken.notional = fCash;
        liquidityToken.storageState = AssetStorageState.Update;

        return (assetCash, market);
    }

    /// @notice Settles a portfolio array
    function settlePortfolio(PortfolioState memory portfolioState, uint256 blockTime)
        internal
        returns (SettleAmount[] memory)
    {
        AssetRateParameters memory settlementRate;
        SettleAmount[] memory settleAmounts = _getSettleAmountArray(portfolioState, blockTime);
        if (settleAmounts.length == 0) return settleAmounts;
        uint256 settleAmountIndex;

        for (uint256 i; i < portfolioState.storedAssets.length; i++) {
            PortfolioAsset memory asset = portfolioState.storedAssets[i];
            // @audit-ok settlement date is on block time exactly
            if (asset.getSettlementDate() > blockTime) continue;

            // @audit on the first loop the lastCurrencyId is already set.
            if (settleAmounts[settleAmountIndex].currencyId != asset.currencyId) {
                // New currency in the portfolio
                settleAmountIndex += 1;
                settleAmounts[settleAmountIndex].currencyId = asset.currencyId;
            }

            // @audit-ok
            settlementRate = AssetRate.buildSettlementRateStateful(
                asset.currencyId,
                asset.maturity,
                blockTime
            );

            int256 assetCash;
            if (asset.assetType == Constants.FCASH_ASSET_TYPE) {
                // @audit-ok
                assetCash = settlementRate.convertFromUnderlying(asset.notional);
                portfolioState.deleteAsset(i);
            } else if (AssetHandler.isLiquidityToken(asset.assetType)) {
                SettlementMarket memory market;
                // @audit-ok assets mature exactly on block time
                if (asset.maturity > blockTime) {
                    (assetCash, market) = _settleLiquidityTokenTofCash(portfolioState, i);
                } else {
                    (assetCash, market) = _settleLiquidityToken(asset, settlementRate);
                    // @audit-ok asset is deleted
                    portfolioState.deleteAsset(i);
                }

                // @audit if we use remove liquidity and have it set then this is redundant
                Market.setSettlementMarket(market);
            }

            // @audit-ok
            settleAmounts[settleAmountIndex].netCashChange = settleAmounts[settleAmountIndex]
                .netCashChange
                .add(assetCash);
        }

        return settleAmounts;
    }
}
