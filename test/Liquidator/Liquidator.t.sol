// SPDX-License-Identifier: MIT
pragma solidity =0.7.6;
pragma abicoder v2;

import {Test} from "forge-std/Test.sol";
import {IFlashLender} from "../../interfaces/aave/IFlashLender.sol";
import {FlashLiquidator} from "../../contracts/external/liquidators/FlashLiquidator.sol";
import "../../interfaces/notional/NotionalProxy.sol";
import "../../interfaces/notional/ITradingModule.sol";
import "../../contracts/external/liquidators/BaseLiquidator.sol";

struct UniData {
    uint24 fee;
}

contract LiquidatorTest is Test { 
    FlashLiquidator public liquidator;
    address public owner;
    IFlashLender public constant lendingPool = IFlashLender(0x87870Bca3F3fD6335C3F4ce8392D69350B4fA4E2);
    NotionalProxy public constant notional = NotionalProxy(0x6e7058c91F85E0F6db4fc9da2CA41241f5e4263f);
    ITradingModule public constant tradingModule = ITradingModule(0x594734c7e06C3D483466ADBCe401C6Bd269746C8);

    function setUp() public {
        vm.createSelectFork(
            "https://mainnet.infura.io/v3/13cbb350551a4b0a8f383db6651de5dc",
            19322409
        );
        owner = makeAddr("owner");

        liquidator = new FlashLiquidator(
            notional,
            address(lendingPool),
            0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2,
            owner,
            address(tradingModule)
        );
        uint16[] memory c = new uint16[](4);
        for (uint16 i = 1; i <= 4; i++) c[i - 1] = i;
        vm.prank(owner);
        liquidator.enableCurrencies(c);

        vm.prank(0x22341fB5D92D3d801144aA5A925F401A91418A05);
        tradingModule.setTokenPermissions(
            address(liquidator),
            address(0),
            ITradingModule.TokenPermissions(true, uint32(1 << uint8(DexId.UNISWAP_V3)), 15)
        );
    }

    function test_LocalLiquidation() public {
        address acct = makeAddr("account");
        deal(acct, 1e18);

        vm.startPrank(acct);
        notional.enablePrimeBorrow(true);
        BalanceAction[] memory balanceActions = new BalanceAction[](1);
        BalanceAction memory balanceAction =
            BalanceAction(DepositActionType.DepositUnderlyingAndMintNToken, 1, 0.5e18, 0, false, true);
        balanceActions[0] = balanceAction;
        notional.batchBalanceAction{value: 0.5e18}(acct, balanceActions);
        notional.withdraw(1, 0.4499e8, true);
        vm.warp(block.timestamp + 86400 * 60);
        vm.stopPrank();

        notional.initializeMarkets(1, false);

        address[] memory assets = new address[](1);
        uint256[] memory amounts = new uint256[](1);
        assets[0] = address(liquidator.WETH());
        amounts[0] = 0.2e18;
        LocalCurrencyLiquidation memory local = LocalCurrencyLiquidation(acct, 1, 0);
        LiquidationAction memory params = LiquidationAction(
            uint8(LiquidationType.LocalCurrency),
            true,
            false,
            true,
            "",
            abi.encode(local)
        );

        vm.prank(owner);
        lendingPool.flashLoan(
            address(liquidator),
            assets,
            amounts,
            new uint256[](1),
            address(liquidator),
            abi.encode(params),
            0
        );
    }

    function test_CurrencyLiquidation() public {
        address acct = makeAddr("account");
        deal(acct, 1e18);

        vm.startPrank(acct);
        notional.enablePrimeBorrow(true);
        BalanceAction[] memory balanceActions = new BalanceAction[](1);
        BalanceAction memory balanceAction =
            BalanceAction(DepositActionType.DepositUnderlyingAndMintNToken, 1, 0.04e18, 0, false, true);
        balanceActions[0] = balanceAction;
        notional.batchBalanceAction{value: 0.04e18}(acct, balanceActions);
        notional.withdraw(3, 93.2e8, true);
        vm.warp(block.timestamp + 86400 * 7);
        vm.stopPrank();

        address[] memory assets = new address[](1);
        uint256[] memory amounts = new uint256[](1);
        assets[0] = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
        amounts[0] = 47e6;
        UniData memory uni = UniData(500);
        CollateralCurrencyLiquidation memory collateral = CollateralCurrencyLiquidation(
            acct,
            3,
            1,
            address(0),
            0,
            0,
            TradeData(
                Trade(TradeType.EXACT_IN_SINGLE, address(0), assets[0], 0.01469e18, 0, block.timestamp, abi.encode(uni)),
                uint16(DexId.UNISWAP_V3),
                false,
                0
            )
        );
        LiquidationAction memory params = LiquidationAction(
            uint8(LiquidationType.CollateralCurrency),
            false,
            false,
            false,
            "",
            abi.encode(collateral)
        );

        vm.prank(owner);
        lendingPool.flashLoan(
            address(liquidator),
            assets,
            amounts,
            new uint256[](1),
            address(liquidator),
            abi.encode(params),
            0
        );
    }
}