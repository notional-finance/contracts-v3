// SPDX-License-Identifier: GPL-3.0-only
pragma solidity >=0.7.6;
pragma abicoder v2;

import {Script} from "forge-std/Script.sol";
import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";

import {Deployments} from "../contracts/global/Deployments.sol";
import {AaveV3HoldingsOracle} from "../contracts/external/pCash/AaveV3HoldingsOracle.sol";
import {IPrimeCashHoldingsOracle} from "../interfaces/notional/IPrimeCashHoldingsOracle.sol";
import {NotionalProxy, NotionalTreasury} from "../interfaces/notional/NotionalProxy.sol";
import {ILendingPool} from "../interfaces/aave/ILendingPool.sol";
import {IERC20} from "../interfaces/IERC20.sol";

interface RebalanceHelper {
    function RELAYER_ADDRESS() external view returns (address);
    function checkAndRebalance() external;
}

contract DeployAaveHoldingOracles is Script, Test {
    RebalanceHelper rebalancingBot = RebalanceHelper(0x366d5b255D97C5fee2283561Bd89fCe5566b178F);
    AaveV3HoldingsOracle newOracle;
    IERC20 aToken;
    NotionalProxy NOTIONAL;

    function setUp() external {
        vm.createSelectFork("https://arb-mainnet.g.alchemy.com/v2/pq08EwFvymYFPbDReObtP-SFw3bCes8Z", 261758243);
        uint256 chainId;
        assembly {
            chainId := chainid()
        }

        require(Deployments.ARBITRUM_ONE == chainId, "Wrong chain");

        string memory json = vm.readFile("v3.arbitrum-one.json");
        NOTIONAL = NotionalProxy(address(vm.parseJsonAddress(json, ".notional")));
        address AAVE_LENDING_POOL = address(vm.parseJsonAddress(json, ".aaveLendingPool"));
        address POOL_DATA_PROVIDER = address(vm.parseJsonAddress(json, ".aavePoolDataProvider"));
        uint16 currencyId = 3; // USDC

        // vm.startBroadcast();
        address underlying = IPrimeCashHoldingsOracle(NOTIONAL.getPrimeCashHoldingsOracle(currencyId)).underlying();
        aToken = IERC20(ILendingPool(AAVE_LENDING_POOL).getReserveData(underlying).aTokenAddress);

        require(address(aToken) != address(0), "Token not supported");

        newOracle = new AaveV3HoldingsOracle(
            NOTIONAL, underlying, AAVE_LENDING_POOL, address(aToken), POOL_DATA_PROVIDER
        );

        // vm.stopBroadcast();

        vm.startPrank(NOTIONAL.owner());
        newOracle.setMaxAbsoluteDeposit(100e6); // Max deposit of 100 USDC
        NOTIONAL.setRebalancingBot(address(rebalancingBot));
        NOTIONAL.setRebalancingCooldown(currencyId, 4 hours);
        NOTIONAL.updatePrimeCashHoldingsOracle(currencyId, newOracle);
        NotionalTreasury.RebalancingTargetConfig[] memory targets = new NotionalTreasury.RebalancingTargetConfig[](1);
        // 80% utilization, 120% external withdraw threshold
        targets[0] = NotionalTreasury.RebalancingTargetConfig(address(aToken), 90, 120);
        NOTIONAL.setRebalancingTargets(currencyId, targets);
        vm.stopPrank();

        // test_RebalanceAfterCooldown();
        // test_RebalanceBeforeCooldown();
        // Tests:
        // 1. Check that we can run an initial rebalance and it deposits 100 USDC
        // 2. Check that we can run a rebalance after the cooldown and it deposits 100 USDC
        // 3. Check that we can run a rebalance before the cooldown and it does not deposit
        // 4. Deposit more USDC and check that the deposit does not exceed 100 USDC
        // 5. Withdraw USDC and check that the withdrawal does not exceed 100 USDC
    }

    function test_InitialRebalance() public {
        vm.startPrank(rebalancingBot.RELAYER_ADDRESS());
        rebalancingBot.checkAndRebalance();

        assertEq(aToken.balanceOf(address(NOTIONAL)), 100e6);
    }

    function test_RebalanceAfterCooldown() public {
        vm.warp(block.timestamp + 4 hours + 10);
        vm.prank(rebalancingBot.RELAYER_ADDRESS());
        rebalancingBot.checkAndRebalance();

        assertGt(aToken.balanceOf(address(NOTIONAL)), 100e6);
    }

    function test_RebalanceBeforeCooldown() public {
        vm.warp(block.timestamp + 1 hours);
        vm.prank(rebalancingBot.RELAYER_ADDRESS());
        rebalancingBot.checkAndRebalance();

        assertGt(aToken.balanceOf(address(NOTIONAL)), 100e6);
    }

    // function test_DepositExceedsMaxDeposit() external {
    // }

    // function test_WithdrawExceedsMaxDeposit() external {
    // }
}
