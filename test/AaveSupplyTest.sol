// SPDX-License-Identifier: MIT
pragma solidity =0.7.6;
pragma abicoder v2;

import {Test} from "forge-std/Test.sol";

import {IERC20} from "../interfaces/IERC20.sol";
import {IPoolDataProvider} from "../interfaces/aave/IPoolDataProvider.sol";
import {ILendingPool} from "../interfaces/aave/ILendingPool.sol";

contract AaveSupply is Test {
    address internal AAVE_LENDING_POOL;
    address internal POOL_DATA_PROVIDER;

    string internal ARBITRUM_RPC_URL = vm.envString("ARBITRUM_RPC_URL");
    uint256 internal ARBITRUM_FORK_BLOCK = 175759842;
    uint256 internal constant RAY = 1e27;
    uint256 internal constant HALF_RAY = 0.5e27;

    address underlying = 0xaf88d065e77c8cC2239327C5EDb3A432268e5831; // usdc
    address depositor = 0xB38e8c17e38363aF6EbdCb3dAE12e0243582891D; // usdc whale


    function setUp() public virtual {
        vm.createSelectFork(ARBITRUM_RPC_URL, ARBITRUM_FORK_BLOCK);

        string memory json = vm.readFile("v3.arbitrum-one.json");
        AAVE_LENDING_POOL = address(vm.parseJsonAddress(json, ".aaveLendingPool"));
        POOL_DATA_PROVIDER = address(vm.parseJsonAddress(json, ".aavePoolDataProvider"));
    }


    function testFork_AaveSupplyCapCalculation_AccruedToTreasuryIsProperlyUpdated() public {
        vm.startPrank(depositor);
        IERC20(underlying).approve(AAVE_LENDING_POOL, type(uint256).max);

        // force accruedToTreasury to be update to current block
        ILendingPool(AAVE_LENDING_POOL).deposit(underlying, 1, depositor, 0);

        (/* */, uint256 supplyCap) = IPoolDataProvider(POOL_DATA_PROVIDER).getReserveCaps(underlying);
        (/* */, uint256 accruedToTreasury, uint256 totalAToken,/* */,/* */,/* */,/* */,/* */,/* */,/* */,/* */,/* */) =
            IPoolDataProvider(POOL_DATA_PROVIDER).getReserveData(underlying);
        uint256 income = ILendingPool(AAVE_LENDING_POOL).getReserveNormalizedIncome(underlying);
        supplyCap = supplyCap * (10 ** 6);

        uint256 amount = supplyCap - totalAToken - rayMul(accruedToTreasury, income);
        ILendingPool(AAVE_LENDING_POOL).deposit(underlying, amount, depositor, 0);


        vm.expectRevert(bytes("51"));
        // pool is already full so here deposit should revert
        ILendingPool(AAVE_LENDING_POOL).deposit(underlying, 1, depositor, 0);
    }

    function testFork_AaveSupplyCapCalculationGasOptimized_AccruedToTreasuryIsNotProperlyUpdated() public {
        vm.startPrank(depositor);
        IERC20(underlying).approve(AAVE_LENDING_POOL, type(uint256).max);

        (/* */, uint256 supplyCap) = IPoolDataProvider(POOL_DATA_PROVIDER).getReserveCaps(underlying);
        (/* */, uint256 accruedToTreasury, uint256 totalAToken,/* */,/* */,/* */,/* */,/* */,/* */,/* */,/* */,/* */) =
            IPoolDataProvider(POOL_DATA_PROVIDER).getReserveData(underlying);
        uint256 income = ILendingPool(AAVE_LENDING_POOL).getReserveNormalizedIncome(underlying);
        supplyCap = supplyCap * (10 ** 6);

        uint256 amount = supplyCap - (totalAToken - rayMul(accruedToTreasury, income)) * 1001 / 1000;
        ILendingPool(AAVE_LENDING_POOL).deposit(underlying, amount, depositor, 0);
    }


    function rayMul(uint256 a, uint256 b) internal pure returns (uint256 c) {
        // to avoid overflow, a <= (type(uint256).max - HALF_RAY) / b
        assembly {
            if iszero(or(iszero(b), iszero(gt(a, div(sub(not(0), HALF_RAY), b))))) {
                revert(0, 0)
            }

            c := div(add(mul(a, b), HALF_RAY), RAY)
        }
    }
}