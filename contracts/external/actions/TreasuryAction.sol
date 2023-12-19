// SPDX-License-Identifier: BSUL-1.1
pragma solidity =0.7.6;
pragma abicoder v2;

import {
    Token,
    PrimeRate,
    PrimeCashFactorsStorage,
    PrimeCashFactors,
    RebalancingTargetData,
    RebalancingContextStorage
} from "../../global/Types.sol";
import {StorageLayoutV2} from "../../global/StorageLayoutV2.sol";
import {LibStorage} from "../../global/LibStorage.sol";
import {Constants} from "../../global/Constants.sol";
import {SafeInt256} from "../../math/SafeInt256.sol";
import {SafeUint256} from "../../math/SafeUint256.sol";

import {Emitter} from "../../internal/Emitter.sol";
import {BalanceHandler} from "../../internal/balances/BalanceHandler.sol";
import {PrimeRateLib} from "../../internal/pCash/PrimeRateLib.sol";
import {TokenHandler} from "../../internal/balances/TokenHandler.sol";
import {nTokenHandler} from "../../internal/nToken/nTokenHandler.sol";
import {nTokenSupply} from "../../internal/nToken/nTokenSupply.sol";
import {PrimeCashExchangeRate} from "../../internal/pCash/PrimeCashExchangeRate.sol";
import {GenericToken} from "../../internal/balances/protocols/GenericToken.sol";

import {ActionGuards} from "./ActionGuards.sol";
import {NotionalTreasury} from "../../../interfaces/notional/NotionalTreasury.sol";
import {Comptroller} from "../../../interfaces/compound/ComptrollerInterface.sol";
import {IRewarder} from "../../../interfaces/notional/IRewarder.sol";
import {CErc20Interface} from "../../../interfaces/compound/CErc20Interface.sol";
import {IPrimeCashHoldingsOracle, DepositData, RedeemData} from "../../../interfaces/notional/IPrimeCashHoldingsOracle.sol";
import {IRebalancingStrategy, RebalancingData} from "../../../interfaces/notional/IRebalancingStrategy.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {IPrimeCashHoldingsOracle, DepositData, RedeemData, OracleData}
    from "../../../interfaces/notional/IPrimeCashHoldingsOracle.sol";
import {RebalancingData} from "../../../interfaces/notional/IRebalancingStrategy.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import {Math} from "@openzeppelin/contracts/math/Math.sol";

/// @dev moved getTargetExternalLendingAmount to library for easier testing
library TargetHelper {
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

        targetAmount = Math.min(
            // totalPrimeCashInUnderlying and totalPrimeDebtInUnderlying are in 8 decimals, convert it to native
            // token precision here for accurate comparison. No underflow possible since targetExternalUnderlyingLend
            // is floored at zero.
            uint256(underlyingToken.convertToExternal(targetExternalUnderlyingLend)),
            // maxExternalUnderlyingLend is limit enforced by setting externalWithdrawThreshold
            // maxExternalDeposit is limit due to the supply cap on external pools
            Math.min(maxExternalUnderlyingLend, oracleData.maxExternalDeposit)
        );
        // in case of redemption, make sure there is enough to withdraw, important for health check so that
        // it does not trigger rebalances(redemptions) when there is nothing to redeem
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
}

contract TreasuryAction is StorageLayoutV2, ActionGuards, NotionalTreasury {
    using PrimeRateLib for PrimeRate;
    using SafeUint256 for uint256;
    using SafeInt256 for int256;
    using SafeERC20 for IERC20;
    using TokenHandler for Token;

    /// @dev Harvest methods are only callable by the authorized treasury manager contract
    modifier onlyManagerContract() {
        require(treasuryManagerContract == msg.sender, "Treasury manager required");
        _;
    }

    /*****************************************
     * Governance Methods                    *
     *****************************************/

    /// @notice Sets the new treasury manager contract
    function setTreasuryManager(address manager) external override onlyOwner {
        emit TreasuryManagerChanged(treasuryManagerContract, manager);
        treasuryManagerContract = manager;
    }

    /// @notice Set the rebalancing bot to call the rebalance method.
    function setRebalancingBot(address _rebalancingBot) external override onlyOwner {
        rebalancingBot = _rebalancingBot;
    }

    /// @notice Sets the reserve buffer. This is the amount of reserve balance to keep denominated in 1e8
    /// The reserve cannot be harvested if it's below this amount. This portion of the reserve will remain on
    /// the contract to act as a buffer against potential insolvency.
    /// @param currencyId refers to the currency of the reserve
    /// @param bufferAmount reserve buffer amount to keep in internal token precision (1e8)
    function setReserveBuffer(uint16 currencyId, uint256 bufferAmount) external override onlyOwner {
        _checkValidCurrency(currencyId);
        reserveBuffer[currencyId] = bufferAmount;
        emit ReserveBufferUpdated(currencyId, bufferAmount);
    }

    /// @notice Updates the emission rate of incentives for a given currency
    /// @dev emit:UpdateIncentiveEmissionRate
    /// @param currencyId the currency id that the nToken references
    /// @param newEmissionRate Target total incentives to emit for an nToken over an entire year
    /// denominated in WHOLE TOKENS (i.e. setting this to 1 means 1e8 tokens). The rate will not be
    /// exact due to multiplier effects and fluctuating token supply.
    function updateIncentiveEmissionRate(uint16 currencyId, uint32 newEmissionRate) external override onlyOwner {
        _checkValidCurrency(currencyId);
        address nTokenAddress = nTokenHandler.nTokenAddress(currencyId);
        require(nTokenAddress != address(0));
        // Sanity check that emissions rate is not specified in 1e8 terms.
        require(newEmissionRate < Constants.INTERNAL_TOKEN_PRECISION, "Invalid rate");

        nTokenSupply.setIncentiveEmissionRate(nTokenAddress, newEmissionRate, block.timestamp);
        emit UpdateIncentiveEmissionRate(currencyId, newEmissionRate);
    }

    /// @notice This is used in the case of insolvency. It allows the owner to re-align the reserve with its correct balance.
    /// @param currencyId refers to the currency of the reserve
    /// @param newBalance new reserve balance to set, must be less than the current balance
    function setReserveCashBalance(uint16 currencyId, int256 newBalance) external override onlyOwner {
        _checkValidCurrency(currencyId);
        // newBalance cannot be negative and is checked inside BalanceHandler.setReserveCashBalance
        BalanceHandler.setReserveCashBalance(currencyId, newBalance);
    }
    /// @notice Sets the rebalancing parameters that define how often a token is rebalanced. Rebalancing targets a
    /// specific Prime Cash utilization while ensuring that we have the ability to withdraw from an external money
    /// market if we need to.
    function setRebalancingTargets(
        uint16 currencyId,
        RebalancingTargetConfig[] calldata targets
    ) external override onlyOwner {
        address holding =
            PrimeCashExchangeRate.getPrimeCashHoldingsOracle(currencyId).holdings()[0];

        // Currently, the functionality only supports lending on a single external money market. If we want to expand beyond
        // that then how we calculate the rebalancing amounts will have to change.
        require(targets.length == 1);

        mapping(address => RebalancingTargetData) storage rebalancingTargets = LibStorage.getRebalancingTargets()[currencyId];

        RebalancingTargetConfig memory config = targets[0];

        require(config.holding == holding);
        require(config.targetUtilization < 100);
        require(100 <= config.externalWithdrawThreshold);

        rebalancingTargets[holding] = RebalancingTargetData(config.targetUtilization, config.externalWithdrawThreshold);

        emit RebalancingTargetsUpdated(currencyId, targets);

        // Rebalance the currency immediately after we set targets. This allows the owner to immediately exit money
        // markets by setting all the targets to zero. The cooldown check is skipped in this case.
        _rebalanceCurrency({currencyId: currencyId, useCooldownCheck: false});
    }

    /// @notice Sets the time between calls to the rebalance method by the rebalancing bot.
    function setRebalancingCooldown(uint16 currencyId, uint40 cooldownTimeInSeconds) external override onlyOwner {
        mapping(uint16 => RebalancingContextStorage) storage store = LibStorage.getRebalancingContext();
        store[currencyId].rebalancingCooldownInSeconds = cooldownTimeInSeconds;
        emit RebalancingCooldownUpdated(currencyId, cooldownTimeInSeconds);
    }

    /*****************************************
     * Treasury Manager Methods              *
     *****************************************/

    /// @notice Transfers some amount of reserve assets to the treasury manager contract. Reserve assets are
    /// the result of collecting fCash trading fees and vault fees and denominated in Prime Cash. Redeems prime cash
    /// to underlying as it is transferred off the protocol.
    /// @param currencies an array of currencies to transfer from Notional
    function transferReserveToTreasury(uint16[] calldata currencies) external override onlyManagerContract 
        nonReentrant returns (uint256[] memory)
    {
        uint256[] memory amountsTransferred = new uint256[](currencies.length);

        for (uint256 i; i < currencies.length; ++i) {
            // Prevents duplicate currency IDs
            if (i > 0) require(currencies[i] > currencies[i - 1], "IDs must be sorted");

            uint16 currencyId = currencies[i];

            _checkValidCurrency(currencyId);

            // Reserve buffer amount in INTERNAL_TOKEN_PRECISION
            int256 bufferInternal = SafeInt256.toInt(reserveBuffer[currencyId]);

            // Reserve requirement not defined
            if (bufferInternal == 0) continue;

            int256 reserveInternal = BalanceHandler.getPositiveCashBalance(Constants.FEE_RESERVE, currencyId);

            // Do not withdraw anything if reserve is below or equal to reserve requirement
            if (reserveInternal <= bufferInternal) continue;

            // Actual reserve amount allowed to be redeemed and transferred
            // NOTE: overflow not possible with the check above
            int256 primeCashRedeemed = reserveInternal - bufferInternal;

            // Redeems prime cash and transfer underlying to treasury manager contract
            amountsTransferred[i] = _redeemAndTransfer(currencyId, primeCashRedeemed);

            // Updates the reserve balance
            BalanceHandler.harvestExcessReserveBalance(
                currencyId,
                reserveInternal,
                primeCashRedeemed
            );
        }

        // NOTE: TreasuryManager contract will emit an AssetsHarvested event
        return amountsTransferred;
    }

    /// @notice Harvests interest income from rebalancing. Interest income is different from reserve assets because they
    /// are not accounted for with in stored token balances and therefore are not accessible by Prime Cash holders. Any
    /// interest will be transferred to the treasury manager.
    function harvestAssetInterest(uint16[] calldata currencies) external override onlyManagerContract nonReentrant {
        for (uint256 i; i < currencies.length; ++i) {
            // Prevents duplicate currency IDs
            if (i > 0) require(currencies[i] > currencies[i - 1], "IDs must be sorted");

            uint16 currencyId = currencies[i];

            _checkValidCurrency(currencyId);
            _skimInterest(currencyId, PrimeCashExchangeRate.getPrimeCashHoldingsOracle(currencyId));
        }
    }

    /// @notice redeems and transfers tokens to the treasury manager contract
    function _redeemAndTransfer(uint16 currencyId, int256 primeCashRedeemAmount) private returns (uint256) {
        PrimeRate memory primeRate = PrimeRateLib.buildPrimeRateStateful(currencyId);
        Emitter.emitTransferPrimeCash(Constants.FEE_RESERVE, treasuryManagerContract, currencyId, primeCashRedeemAmount);

        int256 actualTransferExternal = TokenHandler.withdrawPrimeCash(
            treasuryManagerContract,
            currencyId,
            primeCashRedeemAmount.neg(),
            primeRate,
            true // if ETH, transfers it as WETH
        ).neg();

        require(actualTransferExternal > 0);
        return uint256(actualTransferExternal);
    }

    /// @notice Transfers any excess balance above the stored token balance to the treasury manager. This
    /// balance is not accessible by Prime Cash holders and represents interest earned by the protocol
    // from lending on external money markets.
    function _skimInterest(uint16 currencyId, IPrimeCashHoldingsOracle oracle) private {
        address[] memory assetTokens = oracle.holdings();

        for (uint256 i; i < assetTokens.length; ++i) {
            address asset = assetTokens[i];

            mapping(address => uint256) storage store = LibStorage.getStoredTokenBalances();
            uint256 storedBalance = store[asset];
            uint256 currentBalance = IERC20(asset).balanceOf(address(this));

            if (currentBalance > storedBalance) {
                uint256 skimAmount = currentBalance - storedBalance;
                GenericToken.safeTransferOut(asset, treasuryManagerContract, skimAmount);
                emit AssetInterestHarvested(currencyId, asset, skimAmount);
            }
        }
    }

    /*****************************************
     * Rebalancing Bot Methods               *
     *****************************************/

    /// @notice View method used by Gelato to check if rebalancing can be executed and get the execution payload.
    function checkRebalance() external view override returns (bool canExec, bytes memory execPayload) {
        mapping(uint16 => RebalancingContextStorage) storage contexts = LibStorage.getRebalancingContext();
        uint16[] memory currencyIds = new uint16[](maxCurrencyId);
        uint16 counter = 0;
        for (uint16 currencyId = 1; currencyId <= maxCurrencyId; currencyId++) {
            IPrimeCashHoldingsOracle oracle = PrimeCashExchangeRate.getPrimeCashHoldingsOracle(currencyId);
            address[] memory holdings = oracle.holdings();
            if (holdings.length == 0) continue;

            RebalancingContextStorage storage context = contexts[currencyId];
            bool cooldownPassed = _hasCooldownPassed(context);

            // If external lending is unhealthy, the bot and rebalance the currency immediately and
            // bypass the cooldown.
            if (cooldownPassed || _isExternalLendingUnhealthy(currencyId, oracle)) {
                currencyIds[counter] = currencyId;
                counter++;
            }
        }

        if (counter != 0) {
            uint16[] memory slicedCurrencyIds = new uint16[](counter);
            for (uint16 i = 0; i < counter; i++) slicedCurrencyIds[i] = currencyIds[i];
            canExec = true;
            execPayload = abi.encodeWithSelector(NotionalTreasury.rebalance.selector, slicedCurrencyIds);
        }
    }

    /// @notice Rebalances the given currency ids. Can only be called by the rebalancing bot. Under normal operating
    /// conditions this can only be called once the cool down period has passed between rebalances, however, if the
    /// external lending is unhealthy we can bypass that cool down period. The logic for when rebalance is called is
    /// defined above in `checkRebalance`.
    /// @param currencyIds sorted array of unique currency id
    function rebalance(uint16[] calldata currencyIds) external override nonReentrant {
        require(msg.sender == rebalancingBot, "Unauthorized");

        for (uint256 i; i < currencyIds.length; ++i) {
            if (i != 0) {
                // ensure currency ids are unique and sorted
                require(currencyIds[i - 1] < currencyIds[i]);
            }


            // Rebalance each of the currencies provided. The gelato bot cannot skip the cooldown check.
            _rebalanceCurrency({currencyId: currencyIds[i], useCooldownCheck: true});
        }
    }

    /// @notice Returns when sufficient time has passed since the last rebalancing cool down.
    function _hasCooldownPassed(RebalancingContextStorage memory context) private view returns (bool) {
        return uint256(context.lastRebalanceTimestampInSeconds)
            .add(context.rebalancingCooldownInSeconds) < block.timestamp;
    }

    /// @notice Executes the rebalancing of a single currency and updates the oracle supply rate.
    function _rebalanceCurrency(uint16 currencyId, bool useCooldownCheck) private {
        RebalancingContextStorage memory context = LibStorage.getRebalancingContext()[currencyId];
        if (useCooldownCheck) {
            require(
                _hasCooldownPassed(context) ||
                _isExternalLendingUnhealthy(currencyId,  PrimeCashExchangeRate.getPrimeCashHoldingsOracle(currencyId))
            );
        }
        // Accrues interest up to the current block before any rebalancing is executed
        PrimeRate memory pr = PrimeRateLib.buildPrimeRateStateful(currencyId);

        // Updates the oracle supply rate as well as the last cooldown timestamp.
        uint256 annualizedInterestRate = _updateOracleSupplyRate(
            currencyId, pr, context.previousSupplyFactorAtRebalance, context.lastRebalanceTimestampInSeconds
        );

        // External effects happen after the internal state has updated
        _executeRebalance(currencyId, pr);

        emit CurrencyRebalanced(currencyId, pr.supplyFactor.toUint(), annualizedInterestRate);
    }

    /// @notice Updates the oracle supply rate for Prime Cash. This oracle supply rate is used to value fCash that exists
    /// below the 3 month fCash tenor. This is not a common situation but it is important to use a TWAP oracle here to
    /// ensure that this fCash is not subject to market manipulation.
    function _updateOracleSupplyRate(
        uint16 currencyId,
        PrimeRate memory pr,
        uint256 previousSupplyFactorAtRebalance,
        uint256 lastRebalanceTimestampInSeconds
    ) private returns (uint256 oracleSupplyRate) {
        // If previous underlying scalar at rebalance == 0, then it is the first rebalance and the
        // oracle supply rate will be left as zero. The previous underlying scalar will
        // be set to the new factors.underlyingScalar in the code below.
        if (previousSupplyFactorAtRebalance != 0) {
            // The interest rate is the rate of increase of the supply factor scaled up to a
            // year time period. Therefore the calculation is:
            //  ((supplyFactor / prevSupplyFactorAtRebalance) - 1) * (year / timeSinceLastRebalance)
            uint256 interestRate = pr.supplyFactor.toUint()
                .mul(Constants.SCALAR_PRECISION)
                .div(previousSupplyFactorAtRebalance)
                .sub(Constants.SCALAR_PRECISION) 
                .div(uint256(Constants.RATE_PRECISION));


            oracleSupplyRate = interestRate
                .mul(Constants.YEAR)
                .div(block.timestamp.sub(lastRebalanceTimestampInSeconds));
        }

        mapping(uint256 => PrimeCashFactorsStorage) storage p = LibStorage.getPrimeCashFactors();
        p[currencyId].oracleSupplyRate = oracleSupplyRate.toUint32();

        mapping(uint16 => RebalancingContextStorage) storage c = LibStorage.getRebalancingContext();
        c[currencyId].lastRebalanceTimestampInSeconds = block.timestamp.toUint40();
        c[currencyId].previousSupplyFactorAtRebalance = pr.supplyFactor.toUint().toUint128();
    }

    /// @notice Calculates and executes the rebalancing of a single currency.
    function _executeRebalance(uint16 currencyId, PrimeRate memory pr) private {
        IPrimeCashHoldingsOracle oracle = PrimeCashExchangeRate.getPrimeCashHoldingsOracle(currencyId);
        OracleData memory oracleData = oracle.getOracleData();

        RebalancingTargetData memory rebalancingTargetData =
            LibStorage.getRebalancingTargets()[currencyId][oracleData.holding];
        PrimeCashFactors memory factors = PrimeCashExchangeRate.getPrimeCashFactors(currencyId);
        Token memory underlyingToken = TokenHandler.getUnderlyingToken(currencyId);

        uint256 targetAmount = TargetHelper.getTargetExternalLendingAmount(
            underlyingToken,
            factors,
            rebalancingTargetData,
            oracleData,
            pr
        );
        RebalancingData memory data = _calculateRebalance(oracle, oracleData, targetAmount);

        uint256 totalUnderlyingValueBefore =
            uint256(underlyingToken.convertToExternal(int256(factors.lastTotalUnderlyingValue)));

        // Process redemptions first
        TokenHandler.executeMoneyMarketRedemptions(underlyingToken, data.redeemData);
        _executeDeposits(underlyingToken, data.depositData);

        (uint256 totalUnderlyingValueAfter, /* */) = oracle.getTotalUnderlyingValueStateful();

        require(totalUnderlyingValueBefore <= totalUnderlyingValueAfter);
    }

    function _isExternalLendingUnhealthy(uint16 currencyId, IPrimeCashHoldingsOracle oracle) internal view
        returns (bool)
    {
        OracleData memory oracleData = oracle.getOracleData();

        if (oracleData.currentExternalUnderlyingLend == 0) return false;

        (PrimeRate memory pr, /* */) = PrimeCashExchangeRate.getPrimeCashRateView(currencyId, block.timestamp);
        RebalancingTargetData memory rebalancingTargetData =
            LibStorage.getRebalancingTargets()[currencyId][oracleData.holding];
        PrimeCashFactors memory factors = PrimeCashExchangeRate.getPrimeCashFactors(currencyId);
        Token memory underlyingToken = TokenHandler.getUnderlyingToken(currencyId);

        uint256 targetAmount = TargetHelper.getTargetExternalLendingAmount(
            underlyingToken,
            factors,
            rebalancingTargetData,
            oracleData,
            pr
        );

        uint256 offTargetPercentage = int256(oracleData.currentExternalUnderlyingLend)
            .sub(int256(targetAmount))
            .abs()
            .toUint()
            .mul(uint256(Constants.PERCENTAGE_DECIMALS))
            .div(targetAmount.add(oracleData.currentExternalUnderlyingLend));

            // TODO: write test for this
        // prevent rebalance if change is not greater than 1%, important for health check and avoiding triggering
        // rebalance shortly after rebalance on minimum change
        return (targetAmount < oracleData.currentExternalUnderlyingLend) && (offTargetPercentage > 0);
    }

    function _calculateRebalance(
        IPrimeCashHoldingsOracle oracle,
        OracleData memory oracleData,
        uint256 targetAmount
    ) private view returns (RebalancingData memory rebalancingData) {
        address holding = oracleData.holding;
        uint256 currentAmount = oracleData.currentExternalUnderlyingLend;

        address[] memory holdings = new address[](1);
        holdings[0] = holding;

        if (targetAmount < currentAmount) {
            uint256[] memory redeemAmounts = new uint256[](1);
            redeemAmounts[0] = currentAmount - targetAmount;

            rebalancingData.redeemData = oracle.getRedemptionCalldataForRebalancing(holdings, redeemAmounts);
        } else if (currentAmount < targetAmount) {
            uint256[] memory depositAmounts = new uint256[](1);
            depositAmounts[0] = targetAmount - currentAmount;

            rebalancingData.depositData = oracle.getDepositCalldataForRebalancing(holdings, depositAmounts);
        }
    }

    function _saveOracleSupplyRate(uint16 currencyId, uint256 annualizedInterestRate) private {
        mapping(uint256 => PrimeCashFactorsStorage) storage store = LibStorage.getPrimeCashFactors();
        store[currencyId].oracleSupplyRate = annualizedInterestRate.toUint32();
    }

    function _saveRebalancingContext(uint16 currencyId, uint128 supplyFactor) private {
        mapping(uint16 => RebalancingContextStorage) storage store = LibStorage.getRebalancingContext();
        store[currencyId].lastRebalanceTimestampInSeconds = block.timestamp.toUint40();
        store[currencyId].previousSupplyFactorAtRebalance = supplyFactor;
    }

    function _executeDeposits(Token memory underlyingToken, DepositData[] memory deposits) private {
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
            // If the call is not the final deposit, then underlyingDepositAmount should
            // be set to zero.
            require(underlyingBalanceChange <= depositData.underlyingDepositAmount);
            // Measure and update the asset token
            uint256 newAssetBalance = IERC20(depositData.assetToken).balanceOf(address(this));
            require(oldAssetBalance <= newAssetBalance);

            if (
                (depositData.rebasingTokenBalanceAdjustment != 0) &&
                (underlyingBalanceChange != newAssetBalance.sub(oldAssetBalance))
            ) {
                newAssetBalance = newAssetBalance.add(depositData.rebasingTokenBalanceAdjustment);
            }

            TokenHandler.updateStoredTokenBalance(depositData.assetToken, oldAssetBalance, newAssetBalance);
            TokenHandler.updateStoredTokenBalance(underlyingToken.tokenAddress, oldUnderlyingBalance, newUnderlyingBalance);
        }
    }

    function _calculateRebalance(
        IPrimeCashHoldingsOracle oracle,
        address[] memory holdings,
        uint8[] memory rebalancingTargets
    ) private view returns (RebalancingData memory rebalancingData) {
        uint256[] memory values = oracle.holdingValuesInUnderlying();

        (
            uint256 totalValue,
            /* uint256 internalPrecision */
        ) = oracle.getTotalUnderlyingValueView();

        address[] memory redeemHoldings = new address[](holdings.length);
        uint256[] memory redeemAmounts = new uint256[](holdings.length);
        address[] memory depositHoldings = new address[](holdings.length);
        uint256[] memory depositAmounts = new uint256[](holdings.length);

        for (uint256 i; i < holdings.length; i++) {
            address holding = holdings[i];
            uint256 targetAmount = totalValue.mul(rebalancingTargets[i]).div(
                uint256(Constants.PERCENTAGE_DECIMALS)
            );
            uint256 currentAmount = values[i];

            redeemHoldings[i] = holding;
            depositHoldings[i] = holding;

            if (targetAmount < currentAmount) {
                redeemAmounts[i] = currentAmount - targetAmount;
            } else if (currentAmount < targetAmount) {
                depositAmounts[i] = targetAmount - currentAmount;
            }
        }

        rebalancingData.redeemData = oracle.getRedemptionCalldataForRebalancing(redeemHoldings, redeemAmounts);
        rebalancingData.depositData = oracle.getDepositCalldataForRebalancing(depositHoldings, depositAmounts);
    }

    /// @notice Sets a secondary incentive rewarder for a currency. This contract will
    /// be called whenever an nToken balance changes and allows a secondary contract to
    /// mint incentives to the account. This will override any previous rewarder, if set.
    /// Will have no effect if there is no nToken corresponding to the currency id.
    /// @dev emit:UpdateSecondaryIncentiveRewarder
    /// @param currencyId currency id of the nToken
    /// @param rewarder rewarder contract
    function setSecondaryIncentiveRewarder(uint16 currencyId, IRewarder rewarder) external override onlyOwner {
        _checkValidCurrency(currencyId);
        if (address(rewarder) != address(0)) {
            require(currencyId == rewarder.CURRENCY_ID());
            require(!rewarder.detached());
        }

        IRewarder currentRewarder = nTokenHandler.getSecondaryRewarder(nTokenHandler.nTokenAddress(currencyId));
        require(address(rewarder) != address(currentRewarder));
        if (address(currentRewarder) != address(0)) {
            currentRewarder.detach();
        }
        nTokenHandler.setSecondaryRewarder(currencyId, rewarder);
        emit UpdateSecondaryIncentiveRewarder(currencyId, address(rewarder));
    }
}