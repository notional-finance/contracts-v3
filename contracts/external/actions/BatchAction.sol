// SPDX-License-Identifier: BSUL-1.1
pragma solidity =0.7.6;
pragma abicoder v2;

import {
    BalanceState,
    PortfolioState,
    AccountContext,
    PrimeRate,
    BatchLend,
    BalanceAction,
    BalanceActionWithTrades,
    DepositActionType,
    TradeActionType,
    Token
} from "../../global/Types.sol";
import {Constants} from "../../global/Constants.sol";
import {SafeInt256} from "../../math/SafeInt256.sol";
import {StorageLayoutV1} from "../../global/StorageLayoutV1.sol";

import {BalanceHandler} from "../../internal/balances/BalanceHandler.sol";
import {TokenHandler} from "../../internal/balances/TokenHandler.sol";
import {PortfolioHandler} from "../../internal/portfolio/PortfolioHandler.sol";
import {PrimeRateLib} from "../../internal/pCash/PrimeRateLib.sol";
import {PrimeSupplyCap} from "../../internal/pCash/PrimeSupplyCap.sol";
import {AccountContextHandler} from "../../internal/AccountContextHandler.sol";
import {NotionalCallback} from "../../../interfaces/notional/NotionalCallback.sol";
import {DeprecatedAssetRate} from "../../internal/markets/DeprecatedAssetRate.sol";

import {TradingAction} from "./TradingAction.sol";
import {ActionGuards} from "./ActionGuards.sol";
import {nTokenMintAction} from "./nTokenMintAction.sol";
import {nTokenRedeemAction} from "./nTokenRedeemAction.sol";
import {SettleAssetsExternal} from "../SettleAssetsExternal.sol";
import {FreeCollateralExternal} from "../FreeCollateralExternal.sol";

contract BatchAction is StorageLayoutV1, ActionGuards {
    using BalanceHandler for BalanceState;
    using PortfolioHandler for PortfolioState;
    using AccountContextHandler for AccountContext;
    using PrimeRateLib for PrimeRate;
    using PrimeSupplyCap for PrimeRate;
    using TokenHandler for Token;
    using SafeInt256 for int256;

    /// @notice Executes a batch of balance transfers including minting and redeeming nTokens.
    /// @param account the account for the action
    /// @param actions array of balance actions to take, must be sorted by currency id
    /// @dev emit:CashBalanceChange, emit:nTokenSupplyChange
    /// @dev auth:msg.sender auth:ERC1155
    function batchBalanceAction(address account, BalanceAction[] calldata actions)
        external
        payable
        nonReentrant
    {
        require(account == msg.sender || msg.sender == address(this), "Unauthorized");
        requireValidAccount(account);

        AccountContext memory accountContext = _settleAccountIfRequired(account);
        BalanceState memory balanceState;

        for (uint256 i = 0; i < actions.length; i++) {
            BalanceAction calldata action = actions[i];
            // msg.value will only be used when currency id == 1, referencing ETH. The requirement
            // to sort actions by increasing id enforces that msg.value will only be used once.
            if (i > 0) {
                require(action.currencyId > actions[i - 1].currencyId, "Unsorted actions");
            }
            // Loads the currencyId into balance state
            balanceState.loadBalanceState(account, action.currencyId, accountContext);

            _executeDepositAction(
                account,
                balanceState,
                action.actionType,
                action.depositActionAmount
            );

            _calculateWithdrawActionAndFinalize(
                account,
                accountContext,
                balanceState,
                action.withdrawAmountInternalPrecision,
                action.withdrawEntireCashBalance,
                action.redeemToUnderlying
            );
        }

        _finalizeAccountContext(account, accountContext);
    }

    /// @notice Executes a batch of balance transfers and trading actions
    /// @param account the account for the action
    /// @param actions array of balance actions with trades to take, must be sorted by currency id
    /// @dev auth:msg.sender auth:ERC1155
    function batchBalanceAndTradeAction(address account, BalanceActionWithTrades[] calldata actions)
        external
        payable
        nonReentrant
    {
        require(account == msg.sender || msg.sender == address(this), "Unauthorized");
        requireValidAccount(account);
        AccountContext memory accountContext = _batchBalanceAndTradeAction(account, actions);
        _finalizeAccountContext(account, accountContext);
    }

    /// @notice Executes a batch of lending actions. This is different from batchBalanceAndTrade because
    /// it always pulls the required amount of tokens to get an account to a cash balance of zero. It reduces
    /// the gas costs for lending because there is no second token transfer where residual balances are sent
    /// back to the account.
    /// @dev Note that this method does not work with native ETH because it requires the ability to pull payment
    /// from an ERC20 token. Therefore, this method is marked as nonpayable. It will still work with cETH or aETH.
    /// @param account the account for the action
    /// @param actions array of batch lending actions
    /// @dev auth:msg.sender auth:ERC1155
    function batchLend(address account, BatchLend[] calldata actions)
        external
        nonReentrant
    {
        require(account == msg.sender || msg.sender == address(this), "Unauthorized");
        requireValidAccount(account);

        AccountContext memory accountContext = _settleAccountIfRequired(account);
        // NOTE: loading the portfolio state must happen after settle account to get the
        // correct portfolio, it will have changed if the account is settled.
        PortfolioState memory portfolioState = PortfolioHandler.buildPortfolioState(
            account,
            accountContext.assetArrayLength,
            0
        );
        BalanceState memory balanceState;

        for (uint256 i = 0; i < actions.length; i++) {
            BatchLend calldata action = actions[i];
            // msg.value will never be used in this method because it is non-payable
            if (i > 0) {
                require(action.currencyId > actions[i - 1].currencyId, "Unsorted actions");
            }

            // Require that each action have at least 1 trade and all trades are lending trades
            uint256 numTrades = action.trades.length;
            require(numTrades > 0); // dev: no actions
            for (uint256 j = 0; j < numTrades; j++) {
                require(uint8(bytes1(action.trades[j])) == uint8(TradeActionType.Lend)); // dev: only lend trades
            }

            // Loads the currencyId into balance state
            balanceState.loadBalanceState(account, action.currencyId, accountContext);
            (balanceState.netCashChange, portfolioState) = _executeTrades(
                account,
                action.currencyId,
                action.trades,
                accountContext,
                portfolioState
            );
            // This must be negative as a result of requiring only lending
            require(balanceState.netCashChange <= 0);

            // Deposit sufficient cash to get the balance up to zero. If required cash is negative (i.e. there
            // is sufficient cash) then we don't need to do anything. The account's cash balance will be net off
            // and there will be no token transfer.
            // NOTE: it is possible that free collateral decreases as a result of lending a cash balance, will
            // check FC at the end of the method.
            int256 requiredCash = balanceState.storedCashBalance.add(balanceState.netCashChange).neg();
            if (requiredCash > 0) {
                int256 primeCashDeposited;
                Token memory underlyingToken = TokenHandler.getUnderlyingToken(action.currencyId);
                int256 underlyingExternalAmount = underlyingToken.convertToUnderlyingExternalWithAdjustment(
                    balanceState.primeRate.convertToUnderlying(requiredCash)
                );

                if (action.depositUnderlying) {
                    // If depositing underlying, get the current asset rate and convert the required cash
                    // back to underlying.
                    primeCashDeposited = balanceState.depositUnderlyingToken(
                        account,
                        underlyingExternalAmount,
                        false // ETH is never used here since the method is non-payable
                    );
                } else {
                    // This code remains to support deprecated asset tokens. AssetRate is no longer used within
                    // Notional, however, it is used here to calculate the proper amount of asset (cTokens) to
                    // deposit in this lending scenario.
                    primeCashDeposited = balanceState.depositDeprecatedAssetToken(
                        account,
                        DeprecatedAssetRate.convertUnderlyingExternalToAsset(
                            action.currencyId,
                            underlyingExternalAmount
                        ).add(1)
                    );
                }

                // Batch lending requires that the balance state does not go below zero, i.e. it does not allow users
                // to borrow variable to lend fixed. That can be accomplished via batchActionWithTrades.
                require(primeCashDeposited >= requiredCash, "Insufficient deposit");
            }

            balanceState.finalizeNoWithdraw(account, accountContext);

            // Check the supply cap after balances have been finalized
            balanceState.primeRate.checkSupplyCap(balanceState.currencyId);
        }

        // Update the portfolio state if bitmap is not enabled. If bitmap is already enabled
        // then all the assets have already been updated in in storage.
        if (!accountContext.isBitmapEnabled()) {
            // NOTE: a new account context memory location is returned here
            accountContext = SettleAssetsExternal.storeAssetsInPortfolioState(
                account, accountContext, portfolioState
            );
        }

        // This will save the account context and check free collateral
        _finalizeAccountContext(account, accountContext);
    }

    /// @notice Executes a batch of balance transfers and trading actions via an authorized callback contract. This
    /// can be used as a "flash loan" facility for special contracts that migrate assets between protocols or perform
    /// other actions on behalf of the user.
    /// Contracts can borrow from Notional and receive a callback prior to an FC check, this can be useful if the contract
    /// needs to perform a trade or repay a debt on a different protocol before depositing collateral. Since Notional's AMM
    /// will never be as capital efficient or gas efficient as other flash loan facilities, this method requires whitelisting
    /// and will mainly be used for contracts that make migrating assets a better user experience.
    /// @param account the account that will take all the actions
    /// @param actions array of balance actions with trades to take, must be sorted by currency id
    /// @param callbackData arbitrary bytes to be passed backed to the caller in the callback
    /// @dev auth:authorizedCallbackContract
    function batchBalanceAndTradeActionWithCallback(
        address account,
        BalanceActionWithTrades[] calldata actions,
        bytes calldata callbackData
    ) external payable {
        // NOTE: Re-entrancy is allowed for authorized callback functions.
        require(authorizedCallbackContract[msg.sender], "Unauthorized");
        requireValidAccount(account);

        AccountContext memory accountContext = _batchBalanceAndTradeAction(account, actions);
        accountContext.setAccountContext(account);

        // Be sure to set the account context before initiating the callback, all stateful updates
        // have been finalized at this point so we are safe to issue a callback. This callback may
        // re-enter Notional safely to deposit or take other actions.
        NotionalCallback(msg.sender).notionalCallback(msg.sender, account, callbackData);

        if (accountContext.hasDebt != 0x00) {
            // NOTE: this method may update the account context to turn off the hasDebt flag, this
            // is ok because the worst case would be causing an extra free collateral check when it
            // is not required. This check will be entered if the account hasDebt prior to the callback
            // being triggered above, so it will happen regardless of what the callback function does.
            FreeCollateralExternal.checkFreeCollateralAndRevert(account);
        }
    }

    function _batchBalanceAndTradeAction(
        address account,
        BalanceActionWithTrades[] calldata actions
    ) internal returns (AccountContext memory) {
        AccountContext memory accountContext = _settleAccountIfRequired(account);
        BalanceState memory balanceState;
        // NOTE: loading the portfolio state must happen after settle account to get the
        // correct portfolio, it will have changed if the account is settled.
        PortfolioState memory portfolioState = PortfolioHandler.buildPortfolioState(
            account,
            accountContext.assetArrayLength,
            0
        );

        for (uint256 i = 0; i < actions.length; i++) {
            BalanceActionWithTrades calldata action = actions[i];
            // msg.value will only be used when currency id == 1, referencing ETH. The requirement
            // to sort actions by increasing id enforces that msg.value will only be used once.
            if (i > 0) {
                require(action.currencyId > actions[i - 1].currencyId, "Unsorted actions");
            }
            // Loads the currencyId into balance state
            balanceState.loadBalanceState(account, action.currencyId, accountContext);

            // Does not revert on invalid action types here, they also have no effect.
            _executeDepositAction(
                account,
                balanceState,
                action.actionType,
                action.depositActionAmount
            );

            if (action.trades.length > 0) {
                int256 netCash;
                (netCash, portfolioState) = _executeTrades(
                    account,
                    action.currencyId,
                    action.trades,
                    accountContext,
                    portfolioState
                );

                // If the account owes cash after trading, ensure that it has enough
                balanceState.netCashChange = balanceState.netCashChange.add(netCash);
            }

            _calculateWithdrawActionAndFinalize(
                account,
                accountContext,
                balanceState,
                action.withdrawAmountInternalPrecision,
                action.withdrawEntireCashBalance,
                action.redeemToUnderlying
            );
        }

        // Update the portfolio state if bitmap is not enabled. If bitmap is already enabled
        // then all the assets have already been updated in in storage.
        if (!accountContext.isBitmapEnabled()) {
            // NOTE: a new account context memory location is returned here
            accountContext = SettleAssetsExternal.storeAssetsInPortfolioState(
                account, accountContext, portfolioState
            );
        }

        // NOTE: free collateral and account context will be set outside of this method call.
        return accountContext;
    }

    /// @dev Executes deposits
    function _executeDepositAction(
        address account,
        BalanceState memory balanceState,
        DepositActionType depositType,
        uint256 depositActionAmount_
    ) private {
        int256 depositActionAmount = SafeInt256.toInt(depositActionAmount_);
        int256 primeCashDeposited;
        require(depositActionAmount >= 0);

        if (depositType == DepositActionType.None) {
            return;
        } else if (
            depositType == DepositActionType.DepositAsset ||
            depositType == DepositActionType.DepositAssetAndMintNToken
        ) {
            // This transfer will happen immediately.
            primeCashDeposited = balanceState.depositDeprecatedAssetToken(
                account,
                depositActionAmount
            );
        } else if (
            depositType == DepositActionType.DepositUnderlying ||
            depositType == DepositActionType.DepositUnderlyingAndMintNToken
        ) {
            // This transfer will be deferred until balanceState.finalize
            primeCashDeposited = balanceState.depositUnderlyingToken(
                account,
                depositActionAmount,
                false // No excess ETH by definition
            );
        } else if (depositType == DepositActionType.ConvertCashToNToken) {
            // _executeNTokenAction will check if the account has sufficient cash
            primeCashDeposited = depositActionAmount;
        }

        _executeNTokenAction(
            account, balanceState, depositType, depositActionAmount, primeCashDeposited
        );
    }

    /// @dev Executes nToken actions
    function _executeNTokenAction(
        address account,
        BalanceState memory balanceState,
        DepositActionType depositType,
        int256 depositActionAmount,
        int256 primeCashDeposited
    ) private {
        // After deposits have occurred, check if we are minting nTokens
        if (
            depositType == DepositActionType.DepositAssetAndMintNToken ||
            depositType == DepositActionType.DepositUnderlyingAndMintNToken ||
            depositType == DepositActionType.ConvertCashToNToken
        ) {
            balanceState.netCashChange = balanceState.netCashChange.sub(primeCashDeposited);

            // Converts a given amount of cash (denominated in internal precision) into nTokens
            int256 tokensMinted = nTokenMintAction.nTokenMint(
                account, balanceState.currencyId, primeCashDeposited
            );

            balanceState.netNTokenSupplyChange = balanceState.netNTokenSupplyChange.add(
                tokensMinted
            );
        } else if (depositType == DepositActionType.RedeemNToken) {
            require(
                // prettier-ignore
                balanceState
                    .storedNTokenBalance
                    .add(balanceState.netNTokenTransfer) // transfers would not occur at this point
                    .add(balanceState.netNTokenSupplyChange) >= depositActionAmount,
                "Insufficient token balance"
            );

            balanceState.netNTokenSupplyChange = balanceState.netNTokenSupplyChange.sub(
                depositActionAmount
            );

            int256 primeCash = nTokenRedeemAction.nTokenRedeemViaBatch(
                account, balanceState.currencyId, depositActionAmount
            );

            balanceState.netCashChange = balanceState.netCashChange.add(primeCash);
        }
    }

    /// @dev Calculations any withdraws and finalizes balances
    function _calculateWithdrawActionAndFinalize(
        address account,
        AccountContext memory accountContext,
        BalanceState memory balanceState,
        uint256 withdrawAmountInternalPrecision,
        bool withdrawEntireCashBalance,
        bool redeemToUnderlying
    ) private {
        int256 withdrawAmount = SafeInt256.toInt(withdrawAmountInternalPrecision);
        require(withdrawAmount >= 0); // dev: withdraw action overflow
        // Prior to the prime cash migration, accounts could withdraw cash as cTokens. This is no longer
        // possible. In the case of ETH, if redeemToUnderlying == false then ETH will be redeemed as WETH.
        if (balanceState.currencyId != Constants.ETH_CURRENCY_ID) {
            require(redeemToUnderlying, "Deprecated: Redemption to cToken");
        }

        // NOTE: if withdrawEntireCashBalance is set it will override the withdrawAmountInternalPrecision input
        if (withdrawEntireCashBalance) {
            // This option is here so that accounts do not end up with dust after lending since we generally
            // cannot calculate exact cash amounts from the liquidity curve.
            withdrawAmount = balanceState.storedCashBalance.add(balanceState.netCashChange);

            // If the account has a negative cash balance then cannot withdraw
            if (withdrawAmount < 0) withdrawAmount = 0;
        }

        balanceState.primeCashWithdraw = withdrawAmount.neg();
        balanceState.finalizeWithWithdraw(account, accountContext, !redeemToUnderlying);

        // Check the supply cap after all balances have been finalized.
        // NOTE: there is an edge condition when attempting to redeem nTokens while the supply cap has
        // been breached that will cause this to revert. Accounts should be able to redeem their nTokens
        // regardless of the supply cap situation. In order to work around this, accounts can call
        // AccountAction#nTokenRedeem and then AccountAction#withdraw, neither of which check supply caps.
        balanceState.primeRate.checkSupplyCap(balanceState.currencyId);
    }

    function _finalizeAccountContext(address account, AccountContext memory accountContext)
        private
    {
        // At this point all balances, market states and portfolio states should be finalized. Just need to check free
        // collateral if required.
        accountContext.setAccountContext(account);
        if (accountContext.hasDebt != 0x00) {
            FreeCollateralExternal.checkFreeCollateralAndRevert(account);
        }
    }

    function _executeTrades(
        address account,
        uint16 currencyId,
        bytes32[] calldata trades,
        AccountContext memory accountContext,
        PortfolioState memory portfolioState
    ) private returns (int256 netCash, PortfolioState memory postTradeState) {
        if (accountContext.isBitmapEnabled()) {
            require(
                accountContext.bitmapCurrencyId == currencyId,
                "Invalid trades for account"
            );
            bool didIncurDebt;
            (netCash, didIncurDebt) = TradingAction.executeTradesBitmapBatch(
                account,
                accountContext.bitmapCurrencyId,
                accountContext.nextSettleTime,
                trades
            );
            if (didIncurDebt) {
                accountContext.hasDebt = Constants.HAS_ASSET_DEBT | accountContext.hasDebt;
            }
        } else {
            // NOTE: we return portfolio state here instead of setting it inside executeTradesArrayBatch
            // because we want to only write to storage once after all trades are completed
            (postTradeState, netCash) = TradingAction.executeTradesArrayBatch(
                account,
                currencyId,
                portfolioState,
                trades
            );
        }
    }

    function _settleAccountIfRequired(address account)
        private
        returns (AccountContext memory)
    {
        AccountContext memory accountContext = AccountContextHandler.getAccountContext(account);
        if (accountContext.mustSettleAssets()) {
            // Returns a new memory reference to account context
            return SettleAssetsExternal.settleAccount(account, accountContext);
        } else {
            return accountContext;
        }
    }

    /// @notice Get a list of deployed library addresses (sorted by library name)
    function getLibInfo() external pure returns (address, address, address, address, address) {
        return (
            address(FreeCollateralExternal), 
            address(SettleAssetsExternal), 
            address(TradingAction),
            address(nTokenMintAction), 
            address(nTokenRedeemAction)
        );
    }
}