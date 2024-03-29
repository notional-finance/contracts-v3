// SPDX-License-Identifier: BSUL-1.1
pragma solidity =0.7.6;
pragma abicoder v2;

import {
    PrimeRate,
    PortfolioState,
    AccountContext,
    MarketParameters,
    CashGroupParameters,
    PrimeRate,
    TradeActionType
} from "../../global/Types.sol";
import {Constants} from "../../global/Constants.sol";
import {SafeInt256} from "../../math/SafeInt256.sol";
import {SafeUint256} from "../../math/SafeUint256.sol";

import {Emitter} from "../../internal/Emitter.sol";
import {BalanceHandler} from "../../internal/balances/BalanceHandler.sol";
import {InterestRateCurve} from "../../internal/markets/InterestRateCurve.sol";
import {Market} from "../../internal/markets/Market.sol";
import {DateTime} from "../../internal/markets/DateTime.sol";
import {CashGroup} from "../../internal/markets/CashGroup.sol";
import {PrimeRateLib} from "../../internal/pCash/PrimeRateLib.sol";
import {PortfolioHandler} from "../../internal/portfolio/PortfolioHandler.sol";
import {BitmapAssetsHandler} from "../../internal/portfolio/BitmapAssetsHandler.sol";
import {nTokenHandler} from "../../internal/nToken/nTokenHandler.sol";
import {AccountContextHandler} from "../../internal/AccountContextHandler.sol";

library TradingAction {
    using PortfolioHandler for PortfolioState;
    using AccountContextHandler for AccountContext;
    using Market for MarketParameters;
    using CashGroup for CashGroupParameters;
    using PrimeRateLib for PrimeRate;
    using SafeInt256 for int256;
    using SafeUint256 for uint256;

    /// @dev Used internally to manage stack issues
    struct TradeContext {
        int256 cash;
        int256 fCashAmount;
        int256 fee;
        int256 netCash;
        int256 totalFee;
        uint256 blockTime;
    }

    /// @notice Executes a trade for leveraged vaults (they can only lend or borrow).
    /// @param currencyId the currency id to lend or borrow
    /// @param trade the bytes32 encoded trade data
    function executeVaultTrade(uint16 currencyId, address vault, bytes32 trade)
        external
        returns (int256 netPrimeCash) {
        CashGroupParameters memory cashGroup = CashGroup.buildCashGroupStateful(currencyId);
        MarketParameters memory market;
        TradeActionType tradeType = TradeActionType(uint256(uint8(bytes1(trade))));

        // During a vault trade, the vault executes the trade on behalf of the account
        (netPrimeCash, /* */) = _executeLendBorrowTrade(vault, cashGroup, market, tradeType, block.timestamp, trade);
    }

    /// @notice Executes trades for a bitmapped portfolio, cannot be called directly
    /// @param account account to put fCash assets in
    /// @param bitmapCurrencyId currency id of the bitmap
    /// @param nextSettleTime used to calculate the relative positions in the bitmap
    /// @param trades tightly packed array of trades, schema is defined in global/Types.sol
    /// @return netCash generated by trading
    /// @return didIncurDebt if the bitmap had an fCash position go negative
    function executeTradesBitmapBatch(
        address account,
        uint16 bitmapCurrencyId,
        uint40 nextSettleTime,
        bytes32[] calldata trades
    ) external returns (int256, bool) {
        CashGroupParameters memory cashGroup = CashGroup.buildCashGroupStateful(bitmapCurrencyId);
        MarketParameters memory market;
        bool didIncurDebt;
        TradeContext memory c;
        c.blockTime = block.timestamp;

        for (uint256 i = 0; i < trades.length; i++) {
            uint256 maturity;
            (maturity, c.cash, c.fCashAmount) = _executeTrade(
                account,
                cashGroup,
                market,
                trades[i],
                c.blockTime
            );

            c.fCashAmount = BitmapAssetsHandler.addifCashAsset(
                account,
                bitmapCurrencyId,
                maturity,
                nextSettleTime,
                c.fCashAmount
            );

            didIncurDebt = didIncurDebt || (c.fCashAmount < 0);
            c.netCash = c.netCash.add(c.cash);
        }

        return (c.netCash, didIncurDebt);
    }

    /// @notice Executes trades for a bitmapped portfolio, cannot be called directly
    /// @param account account to put fCash assets in
    /// @param currencyId currency id to trade
    /// @param portfolioState used to update the positions in the portfolio
    /// @param trades tightly packed array of trades, schema is defined in global/Types.sol
    /// @return resulting portfolio state
    /// @return netCash generated by trading
    function executeTradesArrayBatch(
        address account,
        uint16 currencyId,
        PortfolioState memory portfolioState,
        bytes32[] calldata trades
    ) external returns (PortfolioState memory, int256) {
        CashGroupParameters memory cashGroup = CashGroup.buildCashGroupStateful(currencyId);
        MarketParameters memory market;
        TradeContext memory c;
        c.blockTime = block.timestamp;

        for (uint256 i = 0; i < trades.length; i++) {
            TradeActionType tradeType = TradeActionType(uint256(uint8(bytes1(trades[i]))));

            if (
                tradeType == TradeActionType.AddLiquidity ||
                tradeType == TradeActionType.RemoveLiquidity
            ) {
                revert();
            } else {
                uint256 maturity;
                (maturity, c.cash, c.fCashAmount) = _executeTrade(
                    account,
                    cashGroup,
                    market,
                    trades[i],
                    c.blockTime
                );

                portfolioState.addAsset(
                    currencyId,
                    maturity,
                    Constants.FCASH_ASSET_TYPE,
                    c.fCashAmount
                );
            }

            c.netCash = c.netCash.add(c.cash);
        }

        return (portfolioState, c.netCash);
    }

    /// @notice Executes a non-liquidity token trade
    /// @param account the initiator of the trade
    /// @param cashGroup parameters for the trade
    /// @param market market memory location to use
    /// @param trade bytes32 encoding of the particular trade
    /// @param blockTime the current block time
    /// @return maturity of the asset that was traded
    /// @return cashAmount - a positive or negative cash amount accrued to the account
    /// @return fCashAmount - a positive or negative fCash amount accrued to the account
    function _executeTrade(
        address account,
        CashGroupParameters memory cashGroup,
        MarketParameters memory market,
        bytes32 trade,
        uint256 blockTime
    )
        private
        returns (
            uint256 maturity,
            int256 cashAmount,
            int256 fCashAmount
        )
    {
        TradeActionType tradeType = TradeActionType(uint256(uint8(bytes1(trade))));
        if (tradeType == TradeActionType.PurchaseNTokenResidual) {
            (maturity, cashAmount, fCashAmount) = _purchaseNTokenResidual(
                account, cashGroup, blockTime, trade
            );
        } else if (tradeType == TradeActionType.Lend || tradeType == TradeActionType.Borrow) {
            (cashAmount, fCashAmount) = _executeLendBorrowTrade(
                account, cashGroup, market, tradeType, blockTime, trade
            );
            require(cashAmount != 0, "Trade failed, liquidity");

            // This is a little ugly but required to deal with stack issues. We know the market is loaded
            // with the proper maturity inside _executeLendBorrowTrade
            maturity = market.maturity;
        } else {
            revert();
        }
    }

    /// @notice Executes a lend or borrow trade
    /// @param cashGroup parameters for the trade
    /// @param market market memory location to use
    /// @param tradeType whether this is add or remove liquidity
    /// @param blockTime the current block time
    /// @param trade bytes32 encoding of the particular trade
    /// @return cashAmount - a positive or negative cash amount accrued to the account
    /// @return fCashAmount -  a positive or negative fCash amount accrued to the account
    function _executeLendBorrowTrade(
        address account,
        CashGroupParameters memory cashGroup,
        MarketParameters memory market,
        TradeActionType tradeType,
        uint256 blockTime,
        bytes32 trade
    )
        private
        returns (
            int256 cashAmount,
            int256 fCashAmount
        )
    {
        uint256 marketIndex = uint256(uint8(bytes1(trade << 8)));
        // NOTE: this updates the market in memory
        cashGroup.loadMarket(market, marketIndex, false, blockTime);

        fCashAmount = int256(uint88(bytes11(trade << 16)));
        // fCash to account will be negative here
        if (tradeType == TradeActionType.Borrow) fCashAmount = fCashAmount.neg();

        uint256 postFeeInterestRate;
        (cashAmount, postFeeInterestRate) = market.executeTrade(
            account,
            cashGroup,
            fCashAmount,
            market.maturity.sub(blockTime),
            marketIndex
        );

        uint256 rateLimit = uint256(uint32(bytes4(trade << 104)));
        if (rateLimit != 0) {
            if (tradeType == TradeActionType.Borrow) {
                // Do not allow borrows over the rate limit
                require(postFeeInterestRate <= rateLimit, "Trade failed, slippage");
            } else {
                // Do not allow lends under the rate limit
                require(postFeeInterestRate >= rateLimit, "Trade failed, slippage");
            }
        }
    }

    /// @notice Allows an account to purchase ntoken residuals
    /// @param purchaser account that is purchasing the residuals
    /// @param cashGroup parameters for the trade
    /// @param blockTime the current block time
    /// @param trade bytes32 encoding of the particular trade
    /// @return maturity: the date of the idiosyncratic maturity where fCash will be exchanged
    /// @return cashAmount: a positive or negative cash amount that the account will receive or pay
    /// @return fCashAmount: a positive or negative fCash amount that the account will receive
    function _purchaseNTokenResidual(
        address purchaser,
        CashGroupParameters memory cashGroup,
        uint256 blockTime,
        bytes32 trade
    )
        internal
        returns (
            uint256,
            int256,
            int256
        )
    {
        uint256 maturity = uint256(uint32(uint256(trade) >> 216));
        int256 fCashAmountToPurchase = int88(uint88(uint256(trade) >> 128));
        require(maturity > blockTime, "Invalid maturity");
        // Require that the residual to purchase does not fall on an existing maturity (i.e.
        // it is an idiosyncratic maturity)
        require(
            !DateTime.isValidMarketMaturity(cashGroup.maxMarketIndex, maturity, blockTime),
            "Non idiosyncratic maturity"
        );

        address nTokenAddress = nTokenHandler.nTokenAddress(cashGroup.currencyId);
        // prettier-ignore
        (
            /* currencyId */,
            /* incentiveRate */,
            uint256 lastInitializedTime,
            /* assetArrayLength */,
            bytes6 parameters
        ) = nTokenHandler.getNTokenContext(nTokenAddress);

        // Restrict purchasing until some amount of time after the last initialized time to ensure that arbitrage
        // opportunities are not available (by generating residuals and then immediately purchasing them at a discount)
        // This is always relative to the last initialized time which is set at utc0 when initialized, not the
        // reference time. Therefore we will always restrict residual purchase relative to initialization, not reference.
        // This is safer, prevents an attack if someone forces residuals and then somehow prevents market initialization
        // until the residual time buffer passes.
        require(
            blockTime >
                lastInitializedTime.add(
                    uint256(uint8(parameters[Constants.RESIDUAL_PURCHASE_TIME_BUFFER])) * 1 hours
                ),
            "Insufficient block time"
        );

        int256 notional =
            BitmapAssetsHandler.getifCashNotional(nTokenAddress, cashGroup.currencyId, maturity);
        // Check if amounts are valid and set them to the max available if necessary
        if (notional < 0 && fCashAmountToPurchase < 0) {
            // Does not allow purchasing more negative notional than available
            if (fCashAmountToPurchase < notional) fCashAmountToPurchase = notional;
        } else if (notional > 0 && fCashAmountToPurchase > 0) {
            // Does not allow purchasing more positive notional than available
            if (fCashAmountToPurchase > notional) fCashAmountToPurchase = notional;
        } else {
            // Does not allow moving notional in the opposite direction
            revert("Invalid amount");
        }

        // If fCashAmount > 0 then this will return netPrimeCash > 0, if fCashAmount < 0 this will return
        // netPrimeCash < 0. fCashAmount will go to the purchaser and netPrimeCash will go to the nToken.
        int256 netPrimeCashNToken =
            _getResidualPricePrimeCash(
                cashGroup,
                maturity,
                blockTime,
                fCashAmountToPurchase,
                parameters
            );
        
        // Emit proper events for transferring cash and fCash between nToken and purchaser
        Emitter.emitTransferPrimeCash(
            purchaser, nTokenAddress, cashGroup.currencyId, netPrimeCashNToken
        );

        // If fCashAmountToPurchase > 0 then fCash will be transferred from nToken to purchaser. If fCashAmountToPurchase
        // is negative, then purchaser will transfer fCash to the nToken. The addresses will be flipped inside emitTransferfCash
        // in that case.
        Emitter.emitTransferfCash(
            nTokenAddress, purchaser, cashGroup.currencyId, maturity, fCashAmountToPurchase
        );

        _updateNTokenPortfolio(
            nTokenAddress,
            cashGroup.currencyId,
            maturity,
            lastInitializedTime,
            fCashAmountToPurchase,
            netPrimeCashNToken
        );

        return (maturity, netPrimeCashNToken.neg(), fCashAmountToPurchase);
    }

    /// @notice Returns the amount of asset cash required to purchase the nToken residual
    function _getResidualPricePrimeCash(
        CashGroupParameters memory cashGroup,
        uint256 maturity,
        uint256 blockTime,
        int256 fCashAmount,
        bytes6 parameters
    ) internal view returns (int256) {
        uint256 oracleRate = cashGroup.calculateOracleRate(maturity, blockTime);
        // Residual purchase incentive is specified in ten basis point increments
        uint256 purchaseIncentive =
            uint256(uint8(parameters[Constants.RESIDUAL_PURCHASE_INCENTIVE])) *
                Constants.TEN_BASIS_POINTS;

        if (fCashAmount > 0) {
            // When fCash is positive then we add the purchase incentive, the purchaser
            // can pay less cash for the fCash relative to the oracle rate
            oracleRate = oracleRate.add(purchaseIncentive);
        } else if (oracleRate > purchaseIncentive) {
            // When fCash is negative, we reduce the interest rate that the purchaser will
            // borrow at, we do this check to ensure that we floor the oracle rate at zero.
            oracleRate = oracleRate.sub(purchaseIncentive);
        } else {
            // If the oracle rate is less than the purchase incentive floor the interest rate at zero
            oracleRate = 0;
        }

        int256 exchangeRate =
            InterestRateCurve.getfCashExchangeRate(oracleRate, maturity.sub(blockTime));

        // Returns the net asset cash from the nToken perspective, which is the same sign as the fCash amount
        return
            cashGroup.primeRate.convertFromUnderlying(fCashAmount.divInRatePrecision(exchangeRate));
    }

    function _updateNTokenPortfolio(
        address nTokenAddress,
        uint16 currencyId,
        uint256 maturity,
        uint256 lastInitializedTime,
        int256 fCashAmountToPurchase,
        int256 netPrimeCashNToken
    ) private {
        int256 finalNotional = BitmapAssetsHandler.addifCashAsset(
            nTokenAddress,
            currencyId,
            maturity,
            lastInitializedTime,
            fCashAmountToPurchase.neg() // the nToken takes on the negative position
        );

        // Defensive check to ensure that fCash amounts do not flip signs
        require(
            (fCashAmountToPurchase > 0 && finalNotional >= 0) ||
            (fCashAmountToPurchase < 0 && finalNotional <= 0)
        );

        int256 nTokenCashBalance = BalanceHandler.getPositiveCashBalance(nTokenAddress, currencyId);
        nTokenCashBalance = nTokenCashBalance.add(netPrimeCashNToken);

        // This will ensure that the cash balance is not negative
        BalanceHandler.setBalanceStorageForNToken(nTokenAddress, currencyId, nTokenCashBalance);
    }
}
