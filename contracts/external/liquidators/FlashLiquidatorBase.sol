// SPDX-License-Identifier: BSUL-1.1
pragma solidity =0.7.6;
pragma abicoder v2;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import {SafeMath} from "@openzeppelin/contracts/math/SafeMath.sol";
import {
    BaseLiquidator, 
    LiquidationType,
    LiquidationAction, 
    TradeData,
    CollateralCurrencyLiquidation,
    CrossCurrencyfCashLiquidation
} from "./BaseLiquidator.sol";
import {TradeHandler, Trade} from "./TradeHandler.sol";
import {Constants} from "../../global/Constants.sol";
import {SafeInt256} from "../../math/SafeInt256.sol";
import {NotionalProxy} from "../../../interfaces/notional/NotionalProxy.sol";
import {ITradingModule} from "../../../interfaces/notional/ITradingModule.sol";
import {IERC7399} from "../../../interfaces/IERC7399.sol";
import {IWstETH} from "../../../interfaces/IWstETH.sol";

interface IERC7399Receiver {
    function callback(address, address, address, uint256, uint256, bytes memory) external returns (bytes memory);
}

abstract contract FlashLiquidatorBase is BaseLiquidator, IERC7399Receiver {
    using SafeInt256 for int256;
    using SafeMath for uint256;
    using TradeHandler for Trade;
    using SafeERC20 for IERC20;

    ITradingModule public immutable TRADING_MODULE;

    constructor(
        NotionalProxy notional_,
        address weth_,
        address owner_,
        address tradingModule_
    ) BaseLiquidator(notional_, weth_, owner_) {
        TRADING_MODULE = ITradingModule(tradingModule_);
    }

    function _enableCurrency(uint16 currencyId) internal override returns (address) {
        // Enables currency on notional first
        address underlying = super._enableCurrency(currencyId);

        if (underlying == Constants.ETH_ADDRESS) {
            underlying = address(WETH);
        }

        return underlying;
    }

    // Profit estimation
    function flashLoan(
        address flashLenderWrapper,
        address asset, 
        uint256 amount, 
        bytes calldata params, 
        address localAddress, 
        address collateralAddress
    ) external onlyOwner returns (uint256 flashLoanResidual, uint256 localProfit, uint256 collateralProfit) {
        IERC7399(flashLenderWrapper).flash(
            address(this),
            asset,
            amount,
            params,
            this.callback
        );

        flashLoanResidual = IERC20(asset).balanceOf(address(this));
        localProfit = localAddress == address(0) ?
            address(this).balance : IERC20(localAddress).balanceOf(address(this));
        collateralProfit = collateralAddress == address(0) ?
            address(this).balance : IERC20(collateralAddress).balanceOf(address(this));
    }

    function callback(
        address /* initiator */,
        address paymentReceiver,
        address asset,
        uint256 amount,
        uint256 fee,
        bytes calldata params
    ) external override returns (bytes memory) {
        LiquidationAction memory action = abi.decode(params, ((LiquidationAction)));

        if (asset == address(WETH)) {
            WETH.withdraw(amount);
        }

        if (action.preLiquidationTrade.length > 0) {
            TradeData memory tradeData = abi.decode(action.preLiquidationTrade, (TradeData));
            _executeDexTrade(tradeData);
        }

        if (LiquidationType(action.liquidationType) == LiquidationType.LocalCurrency) {
            _liquidateLocal(action, asset);
        } else if (LiquidationType(action.liquidationType) == LiquidationType.CollateralCurrency) {
            _liquidateCollateral(action, asset);
        } else if (LiquidationType(action.liquidationType) == LiquidationType.LocalfCash) {
            _liquidateLocalfCash(action, asset);
        } else if (LiquidationType(action.liquidationType) == LiquidationType.CrossCurrencyfCash) {
            _liquidateCrossCurrencyfCash(action, asset);
        }

        if (action.tradeInWETH) {
            WETH.deposit{value: address(this).balance}();
        }

        if (
            LiquidationType(action.liquidationType) == LiquidationType.CollateralCurrency ||
            LiquidationType(action.liquidationType) == LiquidationType.CrossCurrencyfCash
        ) {
            _dexTrade(action);
        }

        if (!action.tradeInWETH && asset == address(WETH)) {
            WETH.deposit{value: address(this).balance}();
        }

        uint256 amountWithFee = amount.add(fee);
        if (action.withdrawProfit) {
            _withdrawProfit(asset, amountWithFee);
        }

        // Repay the flash lender
        IERC20(asset).safeTransfer(paymentReceiver, amountWithFee);

        return "";
    }

    function _withdrawProfit(address currency, uint256 threshold) internal {
        // Transfer profit to OWNER
        uint256 bal = IERC20(currency).balanceOf(address(this));
        if (bal > threshold) {
            IERC20(currency).safeTransfer(owner, bal.sub(threshold));
        }
    }

    function _dexTrade(LiquidationAction memory action) internal {
        address collateralUnderlyingAddress;

        if (LiquidationType(action.liquidationType) == LiquidationType.CollateralCurrency) {
            CollateralCurrencyLiquidation memory liquidation = abi.decode(
                action.payload,
                (CollateralCurrencyLiquidation)
            );

            collateralUnderlyingAddress = liquidation.collateralUnderlyingAddress;
            _executeDexTrade(liquidation.tradeData);
        } else {
            CrossCurrencyfCashLiquidation memory liquidation = abi.decode(
                action.payload,
                (CrossCurrencyfCashLiquidation)
            );

            collateralUnderlyingAddress = liquidation.fCashUnderlyingAddress;
            _executeDexTrade(liquidation.tradeData);
        }

        if (action.withdrawProfit) {
            _withdrawProfit(collateralUnderlyingAddress, 0);
        }
    }

    function _executeDexTrade(TradeData memory tradeData) internal {
        if (tradeData.useDynamicSlippage) {
            tradeData.trade._executeTradeWithDynamicSlippage({
                dexId: tradeData.dexId,
                tradingModule: TRADING_MODULE,
                dynamicSlippageLimit: tradeData.dynamicSlippageLimit
            });
        } else {
            tradeData.trade._executeTrade({
                dexId: tradeData.dexId,
                tradingModule: TRADING_MODULE
            });
        }
    }
}