// SPDX-License-Identifier: MIT
pragma solidity >=0.7.6;
pragma abicoder v2;

struct AaveReserveConfigurationMap {
    uint256 data;
}

struct AaveReserveData {
    AaveReserveConfigurationMap configuration;
    uint128 liquidityIndex;
    uint128 currentLiquidityRate;
    uint128 variableBorrowIndex;
    uint128 currentVariableBorrowRate;
    uint128 currentStableBorrowRate;
    uint40 lastUpdateTimestamp;
    uint16 id;
    address aTokenAddress;
    address stableDebtTokenAddress;
    address variableDebtTokenAddress;
    address interestRateStrategyAddress;
    uint128 accruedToTreasury;
    uint128 unbacked;
    uint128 isolationModeTotalDebt;
}

interface IAavePool {
    function getReserveData(address asset) external view returns (AaveReserveData memory);
}

