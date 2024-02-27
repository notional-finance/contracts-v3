// SPDX-License-Identifier: BSUL-1.1
pragma solidity =0.7.6;
pragma abicoder v2;

import {
    BalanceState,
    CashGroupParameters,
    MarketParameters,
    nTokenPortfolio,
    PortfolioState,
    PortfolioAsset,
    ifCashStorage,
    AssetStorageState
} from "../../global/Types.sol";
import {Constants} from "../../global/Constants.sol";
import {LibStorage} from "../../global/LibStorage.sol";
import {SafeInt256} from "../../math/SafeInt256.sol";
import {SafeUint256} from "../../math/SafeUint256.sol";
import {Bitmap} from "../../math/Bitmap.sol";

import {Emitter} from "../../internal/Emitter.sol";
import {Market} from "../../internal/markets/Market.sol";
import {DateTime} from "../../internal/markets/DateTime.sol";
import {CashGroup} from "../../internal/markets/CashGroup.sol";
import {nTokenHandler} from "../../internal/nToken/nTokenHandler.sol";
import {nTokenCalculations} from "../../internal/nToken/nTokenCalculations.sol";
import {PortfolioHandler} from "../../internal/portfolio/PortfolioHandler.sol";
import {TransferAssets} from "../../internal/portfolio/TransferAssets.sol";
import {BitmapAssetsHandler} from "../../internal/portfolio/BitmapAssetsHandler.sol";
import {BalanceHandler} from "../../internal/balances/BalanceHandler.sol";
import {PrimeCashExchangeRate} from "../../internal/pCash/PrimeCashExchangeRate.sol";

library nTokenRedeemAction {
    using SafeInt256 for int256;
    using SafeUint256 for uint256;
    using Bitmap for bytes32;
    using BalanceHandler for BalanceState;
    using Market for MarketParameters;
    using CashGroup for CashGroupParameters;
    using PortfolioHandler for PortfolioState;
    using nTokenHandler for nTokenPortfolio;

    /// @notice When redeeming nTokens via the batch they must all be sold to cash and this
    /// method will return the amount of asset cash sold.
    /// @param currencyId the currency associated the nToken
    /// @param tokensToRedeem the amount of nTokens to convert to cash
    /// @return amount of asset cash to return to the account, denominated in internal token decimals
    function nTokenRedeemViaBatch(address account, uint16 currencyId, int256 tokensToRedeem)
        external
        returns (int256)
    {
        (int256 totalPrimeCash, PortfolioAsset[] memory newifCashAssets) = _redeem({
            account: account, currencyId: currencyId, tokensToRedeem: tokensToRedeem,
            sellTokenAssets: true,
            acceptResidualAssets: false
        });

        require(newifCashAssets.length == 0, "Cannot redeem via batch, residual");
        return totalPrimeCash;
    }

    function _redeem(
        address account,
        uint16 currencyId,
        int256 tokensToRedeem,
        bool sellTokenAssets,
        bool acceptResidualAssets
    ) internal returns (int256, PortfolioAsset[] memory) {
        require(tokensToRedeem > 0);
        nTokenPortfolio memory nToken;
        nToken.loadNTokenPortfolioStateful(currencyId);
        // nTokens cannot be redeemed during the period of time where they require settlement.
        require(nToken.getNextSettleTime() > block.timestamp, "Requires settlement");
        require(tokensToRedeem < nToken.totalSupply, "Cannot redeem");
        PortfolioAsset[] memory newifCashAssets;

        // Get the ifCash bits that are idiosyncratic
        bytes32 ifCashBits = nTokenCalculations.getNTokenifCashBits(
            nToken.tokenAddress,
            currencyId,
            nToken.lastInitializedTime,
            block.timestamp,
            nToken.cashGroup.maxMarketIndex
        );

        if (ifCashBits != 0 && acceptResidualAssets) {
            // This will remove all the ifCash assets proportionally from the account
            newifCashAssets = _reduceifCashAssetsProportional(
                nToken.tokenAddress,
                currencyId,
                nToken.lastInitializedTime,
                tokensToRedeem,
                nToken.totalSupply,
                ifCashBits
            );

            // Once the ifCash bits have been withdrawn, set this to zero so that getLiquidityTokenWithdraw
            // simply gets the proportional amount of liquidity tokens to remove
            ifCashBits = 0;
        }

        // Returns the liquidity tokens to withdraw per market and the netfCash amounts. Net fCash amounts are only
        // set when ifCashBits != 0. Otherwise they must be calculated in _withdrawLiquidityTokens
        (int256[] memory tokensToWithdraw, int256[] memory netfCash) = nTokenCalculations.getLiquidityTokenWithdraw(
            nToken, tokensToRedeem, block.timestamp, ifCashBits
        );

        // Returns the totalPrimeCash as a result of withdrawing liquidity tokens and cash. netfCash will be updated
        // in memory if required and will contain the fCash to be sold or returned to the portfolio
        int256 totalPrimeCash = _reduceLiquidAssets(
            nToken,
            tokensToRedeem,
            tokensToWithdraw,
            netfCash,
            ifCashBits == 0, // If there are no residuals then we need to populate netfCash amounts
            block.timestamp
        );

        // Emits the nToken burn before selling or transferring any fCash assets. This ensures that the prime cash
        // transfer events do not double count the transfers between the account and the nToken.
        Emitter.emitNTokenBurn(account, currencyId, totalPrimeCash, tokensToRedeem);
        (totalPrimeCash, newifCashAssets) = _resolveResidualAssets(
            nToken, account, sellTokenAssets, acceptResidualAssets, totalPrimeCash, netfCash, newifCashAssets
        );

        return (totalPrimeCash, newifCashAssets);
    }

    function _resolveResidualAssets(
        nTokenPortfolio memory nToken,
        address account,
        bool sellTokenAssets,
        bool acceptResidualAssets,
        int256 totalPrimeCash,
        int256[] memory netfCash,
        PortfolioAsset[] memory newifCashAssets
    ) internal returns (int256, PortfolioAsset[] memory) {
        bool netfCashRemaining = true;
        if (sellTokenAssets) {
            int256 primeCash;
            // NOTE: netfCash is modified in place and set to zero if the fCash is sold
            (primeCash, netfCashRemaining) = _sellfCashAssets(nToken, netfCash, account);
            totalPrimeCash = totalPrimeCash.add(primeCash);
        }

        require(netfCashRemaining == false, "Residuals");

        return (totalPrimeCash, newifCashAssets);
    }

    /// @notice Removes liquidity tokens and cash from the nToken
    /// @param nToken portfolio object
    /// @param nTokensToRedeem tokens to redeem
    /// @param tokensToWithdraw array of liquidity tokens to withdraw
    /// @param netfCash array of netfCash figures
    /// @param mustCalculatefCash true if netfCash must be calculated in the removeLiquidityTokens step
    /// @param blockTime current block time
    /// @return primeCashShare amount of cash the redeemer will receive from withdrawing cash assets from the nToken
    function _reduceLiquidAssets(
        nTokenPortfolio memory nToken,
        int256 nTokensToRedeem,
        int256[] memory tokensToWithdraw,
        int256[] memory netfCash,
        bool mustCalculatefCash,
        uint256 blockTime
    ) private returns (int256 primeCashShare) {
        // Get asset cash share for the nToken, if it exists. It is required in balance handler that the
        // nToken can never have a negative cash asset cash balance so what we get here is always positive
        // or zero.
        primeCashShare = nToken.cashBalance.mul(nTokensToRedeem).div(nToken.totalSupply);
        if (primeCashShare > 0) {
            nToken.cashBalance = nToken.cashBalance.subNoNeg(primeCashShare);
            BalanceHandler.setBalanceStorageForNToken(
                nToken.tokenAddress,
                nToken.cashGroup.currencyId,
                nToken.cashBalance
            );
        }

        // Get share of liquidity tokens to remove, netfCash is modified in memory during this method if mustCalculatefcash
        // is set to true
        primeCashShare = primeCashShare.add(
            _removeLiquidityTokens(nToken, nTokensToRedeem, tokensToWithdraw, netfCash, blockTime, mustCalculatefCash)
        );

        nToken.portfolioState.storeAssets(nToken.tokenAddress);

        // NOTE: Token supply change will happen when we finalize balances and after minting of incentives
        return primeCashShare;
    }

    /// @notice Removes nToken liquidity tokens and updates the netfCash figures.
    /// @param nToken portfolio object
    /// @param nTokensToRedeem tokens to redeem
    /// @param tokensToWithdraw array of liquidity tokens to withdraw
    /// @param netfCash array of netfCash figures
    /// @param blockTime current block time
    /// @param mustCalculatefCash true if netfCash must be calculated in the removeLiquidityTokens step
    /// @return totalPrimeCashClaims is the amount of asset cash raised from liquidity token cash claims
    function _removeLiquidityTokens(
        nTokenPortfolio memory nToken,
        int256 nTokensToRedeem,
        int256[] memory tokensToWithdraw,
        int256[] memory netfCash,
        uint256 blockTime,
        bool mustCalculatefCash
    ) private returns (int256 totalPrimeCashClaims) {
        MarketParameters memory market;

        for (uint256 i = 0; i < nToken.portfolioState.storedAssets.length; i++) {
            PortfolioAsset memory asset = nToken.portfolioState.storedAssets[i];
            asset.notional = asset.notional.sub(tokensToWithdraw[i]);
            // Cannot redeem liquidity tokens down to zero or this will cause many issues with
            // market initialization.
            require(asset.notional > 0, "Cannot redeem to zero");
            require(asset.storageState == AssetStorageState.NoChange);
            asset.storageState = AssetStorageState.Update;

            // This will load a market object in memory
            nToken.cashGroup.loadMarket(market, i + 1, true, blockTime);
            int256 fCashClaim;
            {
                int256 primeCash;
                // Remove liquidity from the market
                (primeCash, fCashClaim) = market.removeLiquidity(tokensToWithdraw[i]);
                totalPrimeCashClaims = totalPrimeCashClaims.add(primeCash);
            }

            int256 fCashToNToken;
            if (mustCalculatefCash) {
                // Do this calculation if net ifCash is not set, will happen if there are no residuals
                int256 fCashBalance = BitmapAssetsHandler.getifCashNotional(
                    nToken.tokenAddress,
                    nToken.cashGroup.currencyId,
                    asset.maturity
                );
                int256 fCashShare = fCashBalance.mul(nTokensToRedeem).div(nToken.totalSupply);
                // netfCash = fCashClaim + fCashShare
                netfCash[i] = fCashClaim.add(fCashShare);
                fCashToNToken = fCashShare.neg();

                // Rounding errors occur due to a division before multiplication issue in the
                // code path. To calculate the fCash claim the calculations are:
                //   nTokenCalculations._getProportionalLiquidityTokens:
                //      tokensToWithdraw = totalLiquidity * nTokensToRedeem / nToken.totalSupply
                //   Market.removeLiquidity:
                //      fCashClaim = tokensToWithdraw * totalfCash / totalLiquidity
                //
                //   `totalLiquidity` is multiplied and divided which may cause an off by one error
                //   when compared to the more direct fCashShare math:
                //      fCashShare = fCashBalance * nTokensToRedeem / nToken.totalSupply
                //
                // Since all division rounds down, fCashClaim will be less than to fCashShare by
                // exactly one unit. A netfCash of -1 will cause a failure to sell the fCash position. This
                // condition can only present itself when the netfCash position of the nToken is exactly in
                // balance, which occurs for the longest dated fCash market after every initialize markets.
                // Users could "exit" this position by holding the -1 fCash balance but that is a poor UX and
                // not very gas efficient.
                if (
                    fCashBalance.add(fCashClaim).add(market.totalfCash) == 0 &&
                    netfCash[i] == -1
                ) {
                    // Transfers the -1 fCash back to the nToken, this ensures that the total sum of fCash
                    // does not change.
                    netfCash[i] = 0;
                    fCashToNToken = fCashToNToken.sub(1);
                }
            } else {
                // Account will receive netfCash amount. Deduct that from the fCash claim and add the
                // remaining back to the nToken to net off the nToken's position
                // fCashToNToken = -fCashShare
                // netfCash = fCashClaim + fCashShare
                // fCashToNToken = -(netfCash - fCashClaim)
                // fCashToNToken = fCashClaim - netfCash
                fCashToNToken = fCashClaim.sub(netfCash[i]);
            }

            // Removes the account's fCash position from the nToken, will burn negative fCash
            BitmapAssetsHandler.addifCashAsset(
                nToken.tokenAddress,
                asset.currencyId,
                asset.maturity,
                nToken.lastInitializedTime,
                fCashToNToken
            );
        }

        return totalPrimeCashClaims;
    }

    /// @notice Sells fCash assets back into the market for cash. Negative fCash assets will decrease netPrimeCash
    /// as a result. The aim here is to ensure that accounts can redeem nTokens without having to take on
    /// fCash assets.
    function _sellfCashAssets(
        nTokenPortfolio memory nToken,
        int256[] memory netfCash,
        address account
    ) private returns (int256 totalPrimeCash, bool hasResidual) {
        MarketParameters memory market;
        hasResidual = false;

        for (uint256 i = 0; i < netfCash.length; i++) {
            if (netfCash[i] == 0) continue;

            nToken.cashGroup.loadMarket(market, i + 1, false, block.timestamp);
            (int256 netPrimeCash, /* */) = market.executeTrade(
                account,
                nToken.cashGroup,
                // Use the negative of fCash notional here since we want to net it out
                netfCash[i].neg(),
                nToken.portfolioState.storedAssets[i].maturity.sub(block.timestamp),
                i + 1
            );

            if (netPrimeCash == 0) {
                // This means that the trade failed
                hasResidual = true;
            } else {
                // If the sale of the fCash is successful, then emit the transfer here to complete the accounting,
                // otherwise the account will accept residuals and transfers will be emitted there.
                Emitter.emitTransferfCash(
                    nToken.tokenAddress, account, nToken.cashGroup.currencyId, market.maturity, netfCash[i]
                );

                totalPrimeCash = totalPrimeCash.add(netPrimeCash);
                netfCash[i] = 0;
            }
        }
    }

    /// @notice Combines newifCashAssets array with netfCash assets into a single finalfCashAssets array
    function _addResidualsToAssets(
        PortfolioAsset[] memory liquidityTokens,
        PortfolioAsset[] memory newifCashAssets,
        int256[] memory netfCash
    ) internal pure returns (PortfolioAsset[] memory finalfCashAssets) {
        uint256 numAssetsToExtend;
        for (uint256 i = 0; i < netfCash.length; i++) {
            if (netfCash[i] != 0) numAssetsToExtend++;
        }

        uint256 newLength = newifCashAssets.length + numAssetsToExtend;
        finalfCashAssets = new PortfolioAsset[](newLength);
        uint index = 0;
        for (; index < newifCashAssets.length; index++) {
            finalfCashAssets[index] = newifCashAssets[index];
        }

        uint netfCashIndex = 0;
        for (; index < finalfCashAssets.length; ) {
            if (netfCash[netfCashIndex] != 0) {
                PortfolioAsset memory asset = finalfCashAssets[index];
                asset.currencyId = liquidityTokens[netfCashIndex].currencyId;
                asset.maturity = liquidityTokens[netfCashIndex].maturity;
                asset.assetType = Constants.FCASH_ASSET_TYPE;
                asset.notional = netfCash[netfCashIndex];
                index++;
            }

            netfCashIndex++;
        }

        return finalfCashAssets;
    }

    /// @notice Used to reduce an nToken ifCash assets portfolio proportionately when redeeming
    /// nTokens to its underlying assets.
    function _reduceifCashAssetsProportional(
        address nTokenAddress,
        uint16 currencyId,
        uint256 lastInitializedTime,
        int256 tokensToRedeem,
        int256 totalSupply,
        bytes32 assetsBitmap
    ) internal returns (PortfolioAsset[] memory) {
        uint256 index = assetsBitmap.totalBitsSet();
        mapping(address => mapping(uint256 =>
            mapping(uint256 => ifCashStorage))) storage store = LibStorage.getifCashBitmapStorage();

        PortfolioAsset[] memory assets = new PortfolioAsset[](index);
        index = 0;

        uint256 bitNum = assetsBitmap.getNextBitNum();
        while (bitNum != 0) {
            uint256 maturity = DateTime.getMaturityFromBitNum(lastInitializedTime, bitNum);
            ifCashStorage storage fCashSlot = store[nTokenAddress][currencyId][maturity];
            int256 notional = fCashSlot.notional;
            int256 finalNotional;

            {
                int256 notionalToTransfer = notional.mul(tokensToRedeem).div(totalSupply);

                PortfolioAsset memory asset = assets[index];
                asset.currencyId = currencyId;
                asset.maturity = maturity;
                asset.assetType = Constants.FCASH_ASSET_TYPE;
                asset.notional = notionalToTransfer;
                index += 1;
            
                finalNotional = notional.sub(notionalToTransfer);
            }

            // Store the new fCash amount
            fCashSlot.notional = finalNotional.toInt128();

            PrimeCashExchangeRate.updateTotalfCashDebtOutstanding(
                nTokenAddress, currencyId, maturity, notional, finalNotional
            );

            // Turn off the bit and look for the next one
            assetsBitmap = assetsBitmap.setBit(bitNum, false);
            bitNum = assetsBitmap.getNextBitNum();
        }

        return assets;
    }
}
