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
import {ExternalLending} from "../../internal/balances/ExternalLending.sol";
import {nTokenHandler} from "../../internal/nToken/nTokenHandler.sol";
import {nTokenSupply} from "../../internal/nToken/nTokenSupply.sol";
import {PrimeCashExchangeRate} from "../../internal/pCash/PrimeCashExchangeRate.sol";
import {GenericToken} from "../../internal/balances/protocols/GenericToken.sol";

import {ActionGuards} from "./ActionGuards.sol";
import {NotionalTreasury} from "../../../interfaces/notional/NotionalTreasury.sol";
import {IRewarder} from "../../../interfaces/notional/IRewarder.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import {IPrimeCashHoldingsOracle, DepositData, RedeemData, OracleData}
    from "../../../interfaces/notional/IPrimeCashHoldingsOracle.sol";

contract TreasuryAction is StorageLayoutV2, ActionGuards, NotionalTreasury {
    using PrimeRateLib for PrimeRate;
    using SafeUint256 for uint256;
    using SafeInt256 for int256;
    using SafeERC20 for IERC20;
    using TokenHandler for Token;

    struct RebalancingData {
        RedeemData[] redeemData;
        DepositData[] depositData;
    }

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

    /// @notice Redeems and transfers tokens to the treasury manager contract. This method is distinct from _skimInterest
    /// because it redeems prime cash held by the protocol, _skimInterest transfers external lending tokens held by the
    /// protocol.
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

        // Counter is used to calculate the payload at the end of the method
        uint16 counter = 0;

        // Currency ids are 1-indexed
        for (uint16 currencyId = 1; currencyId <= maxCurrencyId; currencyId++) {
            IPrimeCashHoldingsOracle oracle = PrimeCashExchangeRate.getPrimeCashHoldingsOracle(currencyId);
            address[] memory holdings = oracle.holdings();
            if (holdings.length == 0) continue;

            RebalancingContextStorage storage context = contexts[currencyId];
            bool cooldownPassed = _hasCooldownPassed(context);
            (PrimeRate memory pr, /* */) = PrimeCashExchangeRate.getPrimeCashRateView(currencyId, block.timestamp);
            (bool isExternalLendingUnhealthy, /* */, /* */) = _isExternalLendingUnhealthy(currencyId, oracle, pr);

            // If external lending is unhealthy, the bot and rebalance the currency immediately and
            // bypass the cooldown.
            if (cooldownPassed || isExternalLendingUnhealthy) {
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
            // ensure currency ids are unique and sorted
            if (i != 0) require(currencyIds[i - 1] < currencyIds[i]);

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
        // Accrues interest up to the current block before any rebalancing is executed
        IPrimeCashHoldingsOracle oracle = PrimeCashExchangeRate.getPrimeCashHoldingsOracle(currencyId);
        PrimeRate memory pr = PrimeRateLib.buildPrimeRateStateful(currencyId);

        bool hasCooldownPassed = _hasCooldownPassed(context);
        (bool isExternalLendingUnhealthy, OracleData memory oracleData, uint256 targetAmount) = 
            _isExternalLendingUnhealthy(currencyId, oracle, pr);

        // Cooldown check is bypassed when the owner updates the rebalancing targets
        if (useCooldownCheck) require(hasCooldownPassed || isExternalLendingUnhealthy);

        // Updates the oracle supply rate as well as the last cooldown timestamp. Only update the oracle supply rate
        // if the cooldown has passed. If not, the oracle supply rate won't change.
        uint256 oracleSupplyRate = pr.oracleSupplyRate;
        if (hasCooldownPassed) {
            oracleSupplyRate = _updateOracleSupplyRate(
                currencyId, pr, context.previousSupplyFactorAtRebalance, context.lastRebalanceTimestampInSeconds
            );
        }

        // External effects happen after the internal state has updated
        _executeRebalance(currencyId, oracle, pr, oracleData, targetAmount);

        emit CurrencyRebalanced(currencyId, pr.supplyFactor.toUint(), oracleSupplyRate);
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
        // If previous supply factor at rebalance == 0, then it is the first rebalance and the
        // oracle supply rate will be left as zero. The previous supply factor will
        // be set to the new factors.supplyFactor in the code below.
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
    function _executeRebalance(
        uint16 currencyId,
        IPrimeCashHoldingsOracle oracle,
        PrimeRate memory pr,
        OracleData memory oracleData,
        uint256 targetAmount
    ) private {
        Token memory underlyingToken = TokenHandler.getUnderlyingToken(currencyId);
        RebalancingData memory data = _calculateRebalance(oracle, oracleData, targetAmount);
        PrimeCashFactors memory factors = PrimeCashExchangeRate.getPrimeCashFactors(currencyId);

        uint256 totalUnderlyingValueBefore =
            uint256(underlyingToken.convertToExternal(int256(factors.lastTotalUnderlyingValue)));

        // Both of these methods will short circuit if redeemData or depositData has a length of zero
        ExternalLending.executeMoneyMarketRedemptions(underlyingToken, data.redeemData);
        ExternalLending.executeDeposits(underlyingToken, data.depositData);

        // Ensure that total value in underlying terms is not lost as a result of rebalancing.
        (uint256 totalUnderlyingValueAfter, /* */) = oracle.getTotalUnderlyingValueStateful();
        require(totalUnderlyingValueBefore <= totalUnderlyingValueAfter);
    }

    /// @notice Determines if external lending is unhealthy. If this is the case, then we will need to immediately
    /// execute a rebalance.
    function _isExternalLendingUnhealthy(
        uint16 currencyId,
        IPrimeCashHoldingsOracle oracle,
        PrimeRate memory pr
    ) internal view returns (bool isExternalLendingUnhealthy, OracleData memory oracleData, uint256 targetAmount) {
        oracleData = oracle.getOracleData();

        RebalancingTargetData memory rebalancingTargetData =
            LibStorage.getRebalancingTargets()[currencyId][oracleData.holding];
        PrimeCashFactors memory factors = PrimeCashExchangeRate.getPrimeCashFactors(currencyId);
        Token memory underlyingToken = TokenHandler.getUnderlyingToken(currencyId);

        targetAmount = ExternalLending.getTargetExternalLendingAmount(
            underlyingToken, factors, rebalancingTargetData, oracleData, pr
        );

        if (oracleData.currentExternalUnderlyingLend == 0) {
            // If this is zero then there is no outstanding lending.
            isExternalLendingUnhealthy = false;
        } else {
            uint256 offTargetPercentage = oracleData.currentExternalUnderlyingLend.toInt()
                .sub(targetAmount.toInt()).abs()
                .toUint()
                .mul(uint256(Constants.PERCENTAGE_DECIMALS))
                .div(targetAmount.add(oracleData.currentExternalUnderlyingLend));

            // prevent rebalance if change is not greater than 1%, important for health check and avoiding triggering
            // rebalance shortly after rebalance on minimum change
            isExternalLendingUnhealthy = 
                (targetAmount < oracleData.currentExternalUnderlyingLend) && (offTargetPercentage > 0);
        }
    }

    function _calculateRebalance(
        IPrimeCashHoldingsOracle oracle,
        OracleData memory oracleData,
        uint256 targetAmount
    ) private view returns (RebalancingData memory rebalancingData) {
        address holding = oracleData.holding;
        uint256 currentAmount = oracleData.currentExternalUnderlyingLend;

        if (targetAmount < currentAmount) {
            // If above the target amount then redeem
            address[] memory redeemHoldings = new address[](1);
            uint256[] memory redeemAmounts = new uint256[](1);

            redeemHoldings[0] = holding;
            redeemAmounts[0] = currentAmount - targetAmount;
            rebalancingData.redeemData = oracle.getRedemptionCalldataForRebalancing(redeemHoldings, redeemAmounts);
        } else if (currentAmount < targetAmount) {
            // If below the target amount then deposit
            address[] memory depositHoldings = new address[](1);
            uint256[] memory depositAmounts = new uint256[](1);

            depositHoldings[0] = holding;
            depositAmounts[0] = targetAmount - currentAmount;
            rebalancingData.depositData = oracle.getDepositCalldataForRebalancing(depositHoldings, depositAmounts);
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

    /// @notice Sets a secondary incentive rewarder for a currency. This contract will
    /// be called whenever an nToken balance changes and allows a secondary contract to
    /// mint incentives to the account. This will override any previous rewarder, if set.
    /// Will have no effect if there is no nToken corresponding to the currency id.
    /// @dev emit:UpdateSecondaryIncentiveRewarder
    /// @param currencyId currency id of the nToken
    /// @param rewarder rewarder contract
    function setSecondaryIncentiveRewarder(uint16 currencyId, IRewarder rewarder) external override onlyOwner {
        _checkValidCurrency(currencyId);

        address nTokenAddress= nTokenHandler.nTokenAddress(currencyId);
        if (address(rewarder) != address(0)) {
            require(currencyId == rewarder.CURRENCY_ID());
            require(nTokenAddress == rewarder.NTOKEN_ADDRESS());
            require(!rewarder.detached());
        }

        IRewarder currentRewarder = nTokenHandler.getSecondaryRewarder(nTokenAddress);
        require(address(rewarder) != address(currentRewarder));
        if (address(currentRewarder) != address(0)) {
            currentRewarder.detach();
        }
        nTokenHandler.setSecondaryRewarder(currencyId, rewarder);
        emit UpdateSecondaryIncentiveRewarder(currencyId, address(rewarder));
    }
}