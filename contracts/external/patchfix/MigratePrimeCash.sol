// SPDX-License-Identifier: BSUL-1.1
pragma solidity =0.7.6;
pragma abicoder v2;

import {
    InterestRateCurveSettings,
    InterestRateParameters,
    CashGroupSettings,
    Token,
    TokenType,
    TokenStorage,
    MarketParameters,
    AssetRateStorage,
    TotalfCashDebtStorage,
    BalanceStorage,
    PortfolioAssetStorage
} from "../../global/Types.sol";
import {StorageLayoutV2} from "../../global/StorageLayoutV2.sol";
import {Constants} from "../../global/Constants.sol";
import {Deployments} from "../../global/Deployments.sol";
import {LibStorage} from "../../global/LibStorage.sol";
import {SafeUint256} from "../../math/SafeUint256.sol";
import {SafeInt256} from "../../math/SafeInt256.sol";

import {PrimeCashExchangeRate} from "../../internal/pCash/PrimeCashExchangeRate.sol";
import {InterestRateCurve} from "../../internal/markets/InterestRateCurve.sol";
import {TokenHandler} from "../../internal/balances/TokenHandler.sol";
import {CashGroup} from "../../internal/markets/CashGroup.sol";
import {Market} from "../../internal/markets/Market.sol";
import {DateTime} from "../../internal/markets/DateTime.sol";
import {DeprecatedAssetRate} from "../../internal/markets/DeprecatedAssetRate.sol";
import {Emitter} from "../../internal/Emitter.sol";

import {ERC1967Upgrade} from "../../proxy/ERC1967/ERC1967Upgrade.sol";
import {nBeaconProxy} from "../../proxy/nBeaconProxy.sol";
import {UpgradeableBeacon} from "../../proxy/beacon/UpgradeableBeacon.sol";

import {IERC20} from "../../../interfaces/IERC20.sol";
import {IPrimeCashHoldingsOracle} from "../../../interfaces/notional/IPrimeCashHoldingsOracle.sol";
import {AssetRateAdapter} from "../../../interfaces/notional/AssetRateAdapter.sol";

import {MigrationSettings, CurrencySettings, TotalfCashDebt} from "./migrate-v3/MigrationSettings.sol";

contract MigratePrimeCash is StorageLayoutV2, ERC1967Upgrade {
    using SafeUint256 for uint256;
    using SafeInt256 for int256;
    using Market for MarketParameters;
    using TokenHandler for Token;

    uint256 private constant MAX_PORTFOLIO_ASSETS = 8;
    address internal constant NOTIONAL_MANAGER = 0x02479BFC7Dce53A02e26fE7baea45a0852CB0909;

    MigrationSettings public immutable MIGRATION_SETTINGS;
    address public immutable FINAL_ROUTER;
    address public immutable PAUSE_ROUTER;

    event UpdateCashGroup(uint16 currencyId);
    event MigratedToV3();
    event StartV3AccountEvents();
    event EndV3AccountEvents();

    constructor(MigrationSettings settings, address finalRouter, address _pauseRouter) {
        MIGRATION_SETTINGS = settings;
        FINAL_ROUTER = finalRouter;
        PAUSE_ROUTER = _pauseRouter;
    }

    fallback() external { _delegate(PAUSE_ROUTER); }

    function upgradeToRouter() external {
        require(msg.sender == NOTIONAL_MANAGER);
        _upgradeTo(FINAL_ROUTER);
    }

    function _emitCurrencyEvent(address account, uint8 currencyId, uint256 data) private {
        bytes1 mask = (bytes1(bytes32(data)) >> currencyId) & 0x01;
        if (mask == 0x00) return;

        mapping(address => mapping(uint256 => BalanceStorage)) storage store = LibStorage.getBalanceStorage();
        BalanceStorage storage balanceStorage = store[account][currencyId];
        uint256 nTokenBalance = balanceStorage.nTokenBalance;
        if (nTokenBalance > 0) {
            Emitter.emitTransferNToken(address(0), account, currencyId, int256(nTokenBalance));
        }

        int256 cashBalance = balanceStorage.cashBalance;
        if (cashBalance > 0) {
            Emitter.emitMintOrBurnPrimeCash(account, currencyId, cashBalance);
        }
    }

    function _emitFCashEvents(address account, uint256 data) private {
        uint8 length = uint8(bytes1(bytes32(data) << 8));
        if (length == 0) return;

        mapping(address => 
            PortfolioAssetStorage[MAX_PORTFOLIO_ASSETS]) storage store = LibStorage.getPortfolioArrayStorage();
        PortfolioAssetStorage[MAX_PORTFOLIO_ASSETS] storage storageArray = store[account];

        for (uint256 i; i < length; i++) {
            PortfolioAssetStorage storage assetStorage = storageArray[i];
            uint16 currencyId = assetStorage.currencyId;
            uint256 maturity = assetStorage.maturity;
            int256 notional = assetStorage.notional;

            // Only emit fCash mint events here
            uint256 fCashId = Emitter.encodefCashId(currencyId, maturity, notional);
            emit Emitter.TransferSingle(msg.sender, address(0), account, fCashId, uint256(notional.abs()));
        }
    }

    function emitAccountEvents(uint256[] calldata accounts) external {
        require(msg.sender == NOTIONAL_MANAGER);

        // If the subgraph is inside the start and end events, it will only
        // log the prime cash events as a burn of asset cash and a mint of
        // prime cash, that is because nToken and fCash are not changing from
        // V2 to V3
        emit StartV3AccountEvents();

        uint256 len = accounts.length;
        for (uint256 i; i < len; i++) {
            uint256 b = accounts[i];
            address account = address(uint160(b));
            _emitCurrencyEvent(account, 1, b);
            _emitCurrencyEvent(account, 2, b);
            _emitCurrencyEvent(account, 3, b);
            _emitCurrencyEvent(account, 4, b);

            _emitFCashEvents(account, b);
        }

        // When the subgraph sees this event, it will resume normal processing of V3
        // transfer events.
        emit EndV3AccountEvents();
    }

    /// @notice Executes the prime cash migration but does not upgradeTo the final router
    function migratePrimeCash() external {
        require(msg.sender == NOTIONAL_MANAGER);
        require(hasInitialized == false);
        // Fixes a bug in the original router where hasInitialized was never set to true,
        // is not exploitable but this will clean it up.
        hasInitialized = true;

        // Set the new pause router in the proxy storage tree
        pauseRouter = PAUSE_ROUTER;

        // Loop through all all currencies and init the prime cash curve. `maxCurrencyId` is read
        // from the NotionalProxy storage tree.
        uint16 _maxCurrencies = maxCurrencyId;

        // Emit this first to let the subgraph know that the transition to V3 has occurred
        // for updating view function calls.
        emit MigratedToV3();

        for (uint16 currencyId = 1; currencyId <= _maxCurrencies; currencyId++) {
            CurrencySettings memory settings = MIGRATION_SETTINGS.getCurrencySettings(currencyId);

            // Remaps token addresses to the underlying token
            (Token memory assetToken, Token memory underlyingToken) = _remapTokenAddress(currencyId);

            // Initialize the prime cash curve
            _initializePrimeCash(currencyId, assetToken, underlyingToken, settings);

            // Cash group settings have changed and must be set on migration
            _setCashGroup(currencyId, settings.cashGroupSettings);

            // Initialize the new fCash interest rate curves
            _setfCashInterestRateCurves(currencyId);

            // Set the total fCash debt outstanding
            _setTotalfCashDebt(currencyId, settings.fCashDebts);

            // The address for the "fee reserve" has changed in v3, migrate the balance
            // from one storage slot to the other
            _setFeeReserveCashBalance(currencyId);
        }
    }

    function _remapTokenAddress(uint16 currencyId) private returns (
        Token memory assetToken,
        Token memory underlyingToken
    ) {
        // If is Non-Mintable, set the underlying token address
        assetToken = TokenHandler.getDeprecatedAssetToken(currencyId);

        if (assetToken.tokenType == TokenType.NonMintable) {
            // Set the underlying token with the same values as the deprecated
            // asset token
            TokenHandler.setToken(currencyId, TokenStorage({
                tokenAddress: assetToken.tokenAddress,
                hasTransferFee: assetToken.hasTransferFee,
                decimalPlaces: IERC20(assetToken.tokenAddress).decimals(),
                tokenType: TokenType.UnderlyingToken,
                deprecated_maxCollateralBalance: 0
            }));
        }

        // Remap the token address to currency id information
        delete tokenAddressToCurrencyId[assetToken.tokenAddress];
        underlyingToken = TokenHandler.getUnderlyingToken(currencyId);

        tokenAddressToCurrencyId[underlyingToken.tokenAddress] = currencyId;
    }

    function _initializePrimeCash(
        uint16 currencyId,
        Token memory assetToken,
        Token memory underlyingToken,
        CurrencySettings memory settings
    ) private {
        // Will set the initial token balance storage to whatever is on the contract at the time
        // of migration.
        PrimeCashExchangeRate.initTokenBalanceStorage(currencyId, settings.primeCashOracle);

        // Any dust underlying token balances will be donated to the prime supply and aggregated into
        // the underlying scalar value. There is currently some dust ETH balance on Notional that will
        // get donated to all prime cash holders.
        uint88 currentAssetTokenBalance = assetToken.convertToInternal(
            IERC20(assetToken.tokenAddress).balanceOf(address(this)).toInt()
        ).toUint().toUint88();

        // NOTE: at time of upgrade there cannot be any negative cash balances. This can be
        // guaranteed by ensuring that all accounts and negative cash balances are settled
        // before the upgrade is executed. There is no way for the contract to verify that
        // this is the case, must rely on governance to ensure that this occurs.
        PrimeCashExchangeRate.initPrimeCashCurve({
            currencyId: currencyId,
            // The initial prime supply will be set by the current balance of the asset tokens
            // in internal precision. currentAssetTokenBalance / currentTotalUnderlying (both in
            // 8 decimal precision) will set the initial basis for the underlyingScalar. This
            // ensures that all existing cash balances remain in the correct precision.
            totalPrimeSupply: currentAssetTokenBalance,
            // These settings must be set on the implementation storage prior to the upgrade.
            debtCurve: settings.primeDebtCurve,
            oracle: settings.primeCashOracle,
            allowDebt: settings.allowPrimeDebt,
            rateOracleTimeWindow5Min: settings.rateOracleTimeWindow5Min
        });

        bytes memory initCallData = abi.encodeWithSignature(
            "initialize(uint16,address,string,string)",
            currencyId,
            underlyingToken.tokenAddress,
            settings.underlyingName,
            settings.underlyingSymbol
        );

        // A beacon proxy gets its implementation via the UpgradeableBeacon set here.
        nBeaconProxy cashProxy = new nBeaconProxy(address(Deployments.PCASH_BEACON), initCallData);
        PrimeCashExchangeRate.setProxyAddress({
            currencyId: currencyId, proxy: address(cashProxy), isCashProxy: true
        });

        if (settings.allowPrimeDebt) {
            nBeaconProxy debtProxy = new nBeaconProxy(address(Deployments.PDEBT_BEACON), initCallData);
            PrimeCashExchangeRate.setProxyAddress({
                currencyId: currencyId, proxy: address(debtProxy), isCashProxy: false
            });
        }
    }

    function _setCashGroup(uint16 currencyId, CashGroupSettings memory cashGroupSettings) private {
        CashGroup.setCashGroupStorage(currencyId, cashGroupSettings);
        emit UpdateCashGroup(currencyId);
    }

    function _setfCashInterestRateCurves(uint16 currencyId) private {
        (InterestRateCurveSettings[] memory finalCurves, /* */) = MIGRATION_SETTINGS.getfCashCurveUpdate(
            currencyId,
            true // check interest rate divergence
        );

        for (uint256 i; i < finalCurves.length; i++) {
            InterestRateCurve.setNextInterestRateParameters(currencyId, i + 1, finalCurves[i]);
        }

        // Copies the "next interest rate parameters" into the "active" storage slot
        InterestRateCurve.setActiveInterestRateParameters(currencyId);
    }

    /// @notice Sets the total fCash debt outstanding figure which will be used at settlement to
    /// determine the prime cash exchange rate. Prior to the upgrade, Notional will be paused so
    /// that total fCash debt cannot change until this upgrade is completed.
    function _setTotalfCashDebt(uint16 currencyId, TotalfCashDebt[] memory fCashDebts) private {
        mapping(uint256 => mapping(uint256 => TotalfCashDebtStorage)) storage store = LibStorage.getTotalfCashDebtOutstanding();

        for (uint256 i; i < fCashDebts.length; i++) {
            // Only future dated fcash debt should be set
            require(block.timestamp < fCashDebts[i].maturity);
            // Setting the initial fCash amount will not emit any events.
            store[currencyId][fCashDebts[i].maturity].totalfCashDebt = fCashDebts[i].totalfCashDebt;
        }
    }

    function _setFeeReserveCashBalance(uint16 currencyId) internal {
        mapping(address => mapping(uint256 => BalanceStorage)) storage store = LibStorage.getBalanceStorage();
        // Notional V2 reserve constant is set at address(0), copy the value to the new reserve constant
        store[Constants.FEE_RESERVE][currencyId] = store[address(0)][currencyId];
        delete store[address(0)][currencyId];
    }

    /// @dev Delegates the current call to `implementation`.
    /// This function does not return to its internal call site, it will return directly to the external caller.
    function _delegate(address implementation) private {
        // solhint-disable-next-line no-inline-assembly
        assembly {
            // Copy msg.data. We take full control of memory in this inline assembly
            // block because it will not return to Solidity code. We overwrite the
            // Solidity scratch pad at memory position 0.
            calldatacopy(0, 0, calldatasize())

            // Call the implementation.
            // out and outsize are 0 because we don't know the size yet.
            let result := delegatecall(gas(), implementation, 0, calldatasize(), 0, 0)

            // Copy the returned data.
            returndatacopy(0, 0, returndatasize())

            switch result
                // delegatecall returns 0 on error.
                case 0 {
                    revert(0, returndatasize())
                }
                default {
                    return(0, returndatasize())
                }
        }
    }

}