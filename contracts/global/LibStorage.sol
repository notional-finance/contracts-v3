// SPDX-License-Identifier: BSUL-1.1
pragma solidity =0.7.6;
pragma abicoder v2;

import "./Types.sol";
import "./Constants.sol";
import "../../interfaces/notional/IRewarder.sol";
import "../../interfaces/aave/ILendingPool.sol";

library LibStorage {

    /// @dev Offset for the initial slot in lib storage, gives us this number of storage slots
    /// available in StorageLayoutV1 and all subsequent storage layouts that inherit from it.
    uint256 private constant STORAGE_SLOT_BASE = 1000000;
    /// @dev Set to MAX_TRADED_MARKET_INDEX * 2, Solidity does not allow assigning constants from imported values
    uint256 private constant NUM_NTOKEN_MARKET_FACTORS = 14;
    /// @dev Maximum limit for portfolio asset array, this has been reduced from 16 in the previous version. No
    /// account has hit the theoretical limit and it would not possible for them to since accounts do not hold
    /// liquidity tokens (only the nToken does).
    uint256 internal constant MAX_PORTFOLIO_ASSETS = 8;

    /// @dev Storage IDs for storage buckets. Each id maps to an internal storage
    /// slot used for a particular mapping
    ///     WARNING: APPEND ONLY
    enum StorageId {
        Unused,
        AccountStorage,
        nTokenContext,
        nTokenAddress,
        nTokenDeposit,
        nTokenInitialization,
        Balance,
        Token,
        SettlementRate_deprecated,
        CashGroup,
        Market,
        AssetsBitmap,
        ifCashBitmap,
        PortfolioArray,
        // WARNING: this nTokenTotalSupply storage object was used for a buggy version
        // of the incentives calculation. It should only be used for accounts who have
        // not claimed before the migration
        nTokenTotalSupply_deprecated,
        AssetRate_deprecated,
        ExchangeRate,
        nTokenTotalSupply,
        SecondaryIncentiveRewarder,
        LendingPool,
        VaultConfig,
        VaultState,
        VaultAccount,
        VaultBorrowCapacity,
        VaultSecondaryBorrow,
        // With the upgrade to prime cash vaults, settled assets is no longer required
        // for the vault calculation. Do not remove this or other storage slots will be
        // broken.
        VaultSettledAssets_deprecated,
        VaultAccountSecondaryDebtShare,
        ActiveInterestRateParameters,
        NextInterestRateParameters,
        PrimeCashFactors,
        PrimeSettlementRates,
        PrimeCashHoldingsOracles,
        TotalfCashDebtOutstanding,
        pCashAddress,
        pDebtAddress,
        pCashTransferAllowance,
        RebalancingTargets,
        RebalancingContext,
        StoredTokenBalances
    }

    /// @dev Mapping from an account address to account context
    function getAccountStorage() internal pure 
        returns (mapping(address => AccountContext) storage store) 
    {
        uint256 slot = _getStorageSlot(StorageId.AccountStorage);
        assembly { store.slot := slot }
    }

    /// @dev Mapping from an nToken address to nTokenContext
    function getNTokenContextStorage() internal pure
        returns (mapping(address => nTokenContext) storage store) 
    {
        uint256 slot = _getStorageSlot(StorageId.nTokenContext);
        assembly { store.slot := slot }
    }

    /// @dev Mapping from currency id to nTokenAddress
    function getNTokenAddressStorage() internal pure
        returns (mapping(uint256 => address) storage store)
    {
        uint256 slot = _getStorageSlot(StorageId.nTokenAddress);
        assembly { store.slot := slot }
    }

    /// @dev Mapping from currency id to uint32 fixed length array of
    /// deposit factors. Deposit shares and leverage thresholds are stored striped to
    /// reduce the number of storage reads.
    function getNTokenDepositStorage() internal pure
        returns (mapping(uint256 => uint32[NUM_NTOKEN_MARKET_FACTORS]) storage store)
    {
        uint256 slot = _getStorageSlot(StorageId.nTokenDeposit);
        assembly { store.slot := slot }
    }

    /// @dev Mapping from currency id to fixed length array of initialization factors,
    /// stored striped like deposit shares.
    function getNTokenInitStorage() internal pure
        returns (mapping(uint256 => uint32[NUM_NTOKEN_MARKET_FACTORS]) storage store)
    {
        uint256 slot = _getStorageSlot(StorageId.nTokenInitialization);
        assembly { store.slot := slot }
    }

    /// @dev Mapping from account to currencyId to it's balance storage for that currency
    function getBalanceStorage() internal pure
        returns (mapping(address => mapping(uint256 => BalanceStorage)) storage store)
    {
        uint256 slot = _getStorageSlot(StorageId.Balance);
        assembly { store.slot := slot }
    }

    /// @dev Mapping from currency id to a boolean for underlying or asset token to
    /// the TokenStorage
    function getTokenStorage() internal pure
        returns (mapping(uint256 => mapping(bool => TokenStorage)) storage store)
    {
        uint256 slot = _getStorageSlot(StorageId.Token);
        assembly { store.slot := slot }
    }

    /// @dev Mapping from currency id to maturity to its corresponding SettlementRate
    function getSettlementRateStorage_deprecated() internal pure
        returns (mapping(uint256 => mapping(uint256 => SettlementRateStorage)) storage store)
    {
        uint256 slot = _getStorageSlot(StorageId.SettlementRate_deprecated);
        assembly { store.slot := slot }
    }

    /// @dev Mapping from currency id to maturity to its tightly packed cash group parameters
    function getCashGroupStorage() internal pure
        returns (mapping(uint256 => bytes32) storage store)
    {
        uint256 slot = _getStorageSlot(StorageId.CashGroup);
        assembly { store.slot := slot }
    }

    /// @dev Mapping from currency id to maturity to settlement date for a market
    function getMarketStorage() internal pure
        returns (mapping(uint256 => mapping(uint256 => mapping(uint256 => MarketStorage))) storage store)
    {
        uint256 slot = _getStorageSlot(StorageId.Market);
        assembly { store.slot := slot }
    }

    /// @dev Mapping from account to currency id to its assets bitmap
    function getAssetsBitmapStorage() internal pure
        returns (mapping(address => mapping(uint256 => bytes32)) storage store)
    {
        uint256 slot = _getStorageSlot(StorageId.AssetsBitmap);
        assembly { store.slot := slot }
    }

    /// @dev Mapping from account to currency id to its maturity to its corresponding ifCash balance
    function getifCashBitmapStorage() internal pure
        returns (mapping(address => mapping(uint256 => mapping(uint256 => ifCashStorage))) storage store)
    {
        uint256 slot = _getStorageSlot(StorageId.ifCashBitmap);
        assembly { store.slot := slot }
    }

    /// @dev Mapping from account to its fixed length array of portfolio assets
    function getPortfolioArrayStorage() internal pure
        returns (mapping(address => PortfolioAssetStorage[MAX_PORTFOLIO_ASSETS]) storage store)
    {
        uint256 slot = _getStorageSlot(StorageId.PortfolioArray);
        assembly { store.slot := slot }
    }

    function getDeprecatedNTokenTotalSupplyStorage() internal pure
        returns (mapping(address => nTokenTotalSupplyStorage_deprecated) storage store)
    {
        uint256 slot = _getStorageSlot(StorageId.nTokenTotalSupply_deprecated);
        assembly { store.slot := slot }
    }

    /// @dev Mapping from nToken address to its total supply values
    function getNTokenTotalSupplyStorage() internal pure
        returns (mapping(address => nTokenTotalSupplyStorage) storage store)
    {
        uint256 slot = _getStorageSlot(StorageId.nTokenTotalSupply);
        assembly { store.slot := slot }
    }

    /// @dev Returns the exchange rate between an underlying currency and asset for trading
    /// and free collateral. Mapping is from currency id to rate storage object.
    function getAssetRateStorage_deprecated() internal pure
        returns (mapping(uint256 => AssetRateStorage) storage store)
    {
        uint256 slot = _getStorageSlot(StorageId.AssetRate_deprecated);
        assembly { store.slot := slot }
    }

    /// @dev Returns the exchange rate between an underlying currency and ETH for free
    /// collateral purposes. Mapping is from currency id to rate storage object.
    function getExchangeRateStorage() internal pure
        returns (mapping(uint256 => ETHRateStorage) storage store)
    {
        uint256 slot = _getStorageSlot(StorageId.ExchangeRate);
        assembly { store.slot := slot }
    }

    /// @dev Returns the address of a secondary incentive rewarder for an nToken if it exists
    function getSecondaryIncentiveRewarder() internal pure
        returns (mapping(address => IRewarder) storage store)
    {
        uint256 slot = _getStorageSlot(StorageId.SecondaryIncentiveRewarder);
        assembly { store.slot := slot }
    }

    /// @dev Returns the address of the lending pool
    function getLendingPool() internal pure returns (LendingPoolStorage storage store) {
        uint256 slot = _getStorageSlot(StorageId.LendingPool);
        assembly { store.slot := slot }
    }

    /// @dev Returns object for an VaultConfig, mapping is from vault address to VaultConfig object
    function getVaultConfig() internal pure returns (
        mapping(address => VaultConfigStorage) storage store
    ) {
        uint256 slot = _getStorageSlot(StorageId.VaultConfig);
        assembly { store.slot := slot }
    }

    /// @dev Returns object for an VaultState, mapping is from vault address to maturity to VaultState object
    function getVaultState() internal pure returns (
        mapping(address => mapping(uint256 => VaultStateStorage)) storage store
    ) {
        uint256 slot = _getStorageSlot(StorageId.VaultState);
        assembly { store.slot := slot }
    }

    /// @dev Returns object for an VaultAccount, mapping is from account address to vault address to VaultAccount object
    function getVaultAccount() internal pure returns (
        mapping(address => mapping(address => VaultAccountStorage)) storage store
    ) {
        uint256 slot = _getStorageSlot(StorageId.VaultAccount);
        assembly { store.slot := slot }
    }

    /// @dev Returns object for a VaultBorrowCapacity, mapping is from vault address to currency to BorrowCapacity object
    function getVaultBorrowCapacity() internal pure returns (
        mapping(address => mapping(uint256 => VaultBorrowCapacityStorage)) storage store
    ) {
        uint256 slot = _getStorageSlot(StorageId.VaultBorrowCapacity);
        assembly { store.slot := slot }
    }

    /// @dev Returns object for an VaultAccount, mapping is from account address to vault address to maturity to
    /// currencyId to VaultStateStorage object, only totalDebt, totalPrimeCash, and isSettled are used for
    /// vault secondary borrows, but this allows code to be shared.
    function getVaultSecondaryBorrow() internal pure returns (
        mapping(address => mapping(uint256 => mapping(uint256 => VaultStateStorage))) storage store
    ) {
        uint256 slot = _getStorageSlot(StorageId.VaultSecondaryBorrow);
        assembly { store.slot := slot }
    }

    /// @dev Returns object for an VaultAccount, mapping is from account address to vault address
    function getVaultAccountSecondaryDebtShare() internal pure returns (
        mapping(address => mapping(address => VaultAccountSecondaryDebtShareStorage)) storage store
    ) {
        uint256 slot = _getStorageSlot(StorageId.VaultAccountSecondaryDebtShare);
        assembly { store.slot := slot }
    }

    /// @dev Returns object for currently active InterestRateParameters,
    /// mapping is from a currency id to a bytes32[2] array of parameters
    function getActiveInterestRateParameters() internal pure returns (
        mapping(uint256 => bytes32[2]) storage store
    ) {
        uint256 slot = _getStorageSlot(StorageId.ActiveInterestRateParameters);
        assembly { store.slot := slot }
    }

    /// @dev Returns object for the next set of InterestRateParameters,
    /// mapping is from a currency id to a bytes32[2] array of parameters
    function getNextInterestRateParameters() internal pure returns (
        mapping(uint256 => bytes32[2]) storage store
    ) {
        uint256 slot = _getStorageSlot(StorageId.NextInterestRateParameters);
        assembly { store.slot := slot }
    }

    /// @dev Returns mapping from currency id to PrimeCashFactors
    function getPrimeCashFactors() internal pure returns (
        mapping(uint256 => PrimeCashFactorsStorage) storage store
    ) {
        uint256 slot = _getStorageSlot(StorageId.PrimeCashFactors);
        assembly { store.slot := slot }
    }

    /// @dev Returns mapping from currency to maturity to PrimeSettlementRates
    function getPrimeSettlementRates() internal pure returns (
        mapping(uint256 => mapping(uint256 => PrimeSettlementRateStorage)) storage store
    ) {
        uint256 slot = _getStorageSlot(StorageId.PrimeSettlementRates);
        assembly { store.slot := slot }
    }

    /// @dev Returns mapping from currency to an external oracle that reports the
    /// total underlying value for prime cash
    function getPrimeCashHoldingsOracle() internal pure returns (
        mapping(uint256 => PrimeCashHoldingsOracle) storage store
    ) {
        uint256 slot = _getStorageSlot(StorageId.PrimeCashHoldingsOracles);
        assembly { store.slot := slot }
    }

    /// @dev Returns mapping from currency to maturity to total fCash debt outstanding figure.
    function getTotalfCashDebtOutstanding() internal pure returns (
        mapping(uint256 => mapping(uint256 => TotalfCashDebtStorage)) storage store
    ) {
        uint256 slot = _getStorageSlot(StorageId.TotalfCashDebtOutstanding);
        assembly { store.slot := slot }
    }

    /// @dev Returns mapping from currency to pCash proxy address
    function getPCashAddressStorage() internal pure returns (
        mapping(uint256 => address) storage store
    ) {
        uint256 slot = _getStorageSlot(StorageId.pCashAddress);
        assembly { store.slot := slot }
    }

    function getPDebtAddressStorage() internal pure returns (
        mapping(uint256 => address) storage store
    ) {
        uint256 slot = _getStorageSlot(StorageId.pDebtAddress);
        assembly { store.slot := slot }
    }

    /// @dev Returns mapping for pCash ERC20 transfer allowances
    function getPCashTransferAllowance() internal pure returns (
        // owner => spender => currencyId => transferAllowance
        mapping(address => mapping(address => mapping(uint16 => uint256))) storage store
    ) {
        uint256 slot = _getStorageSlot(StorageId.pCashTransferAllowance);
        assembly { store.slot := slot }
    }

    function getRebalancingTargets() internal pure returns (
        mapping(uint16 => mapping(address => RebalancingTargetData)) storage store
    ) {
        uint256 slot = _getStorageSlot(StorageId.RebalancingTargets);
        assembly { store.slot := slot }
    }

    function getRebalancingContext() internal pure returns (
        mapping(uint16 => RebalancingContextStorage) storage store
    ) {
        uint256 slot = _getStorageSlot(StorageId.RebalancingContext);
        assembly { store.slot := slot }
    }

    function getStoredTokenBalances() internal pure returns (
        mapping(address => uint256) storage store
    ) {
        uint256 slot = _getStorageSlot(StorageId.StoredTokenBalances);
        assembly { store.slot := slot }        
    }

    /// @dev Get the storage slot given a storage ID.
    /// @param storageId An entry in `StorageId`
    /// @return slot The storage slot.
    function _getStorageSlot(StorageId storageId)
        private
        pure
        returns (uint256 slot)
    {
        // This should never overflow with a reasonable `STORAGE_SLOT_EXP`
        // because Solidity will do a range check on `storageId` during the cast.
        return uint256(storageId) + STORAGE_SLOT_BASE;
    }
}