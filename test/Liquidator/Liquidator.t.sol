// SPDX-License-Identifier: MIT
pragma solidity =0.7.6;
pragma abicoder v2;

import {Test} from "forge-std/Test.sol";
import {IFlashLender} from "../../interfaces/aave/IFlashLender.sol";
import {IERC7399} from "../../interfaces/IERC7399.sol";
import {FlashLiquidator} from "../../contracts/external/liquidators/FlashLiquidator.sol";
import {IERC7399Receiver} from "../../contracts/external/liquidators/FlashLiquidatorBase.sol";
import "../../interfaces/notional/NotionalProxy.sol";
import "../../interfaces/IEIP20NonStandard.sol";
import "../../interfaces/notional/ITradingModule.sol";
import "../../contracts/external/liquidators/BaseLiquidator.sol";

struct UniData {
    uint24 fee;
}

contract LiquidatorTest is Test { 
    FlashLiquidator public liquidator;
    address public owner;
    IERC7399 public constant lendingPool = IERC7399(0x0c86c636ed5593705b5675d370c831972C787841);
    IERC7399 public constant balancerFlashLender = IERC7399(0x9E092cb431e5F1aa70e47e052773711d2Ba4917E);
    NotionalProxy public constant notional = NotionalProxy(0x6e7058c91F85E0F6db4fc9da2CA41241f5e4263f);
    ITradingModule public constant tradingModule = ITradingModule(0x594734c7e06C3D483466ADBCe401C6Bd269746C8);
    string internal MAINNET_RPC_URL = vm.envString("MAINNET_RPC_URL");

    function setUp() public {
        vm.createSelectFork(MAINNET_RPC_URL, 19322409);
        owner = makeAddr("owner");

        liquidator = new FlashLiquidator(
            notional,
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

        address asset = address(liquidator.WETH());
        uint256 amount = 0.2e18;
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
        lendingPool.flash(
            address(liquidator),
            asset,
            amount,
            abi.encode(params),
            liquidator.callback
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

        address asset = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
        uint256 amount = 47e6;
        UniData memory uni = UniData(500);
        CollateralCurrencyLiquidation memory collateral = CollateralCurrencyLiquidation(
            acct,
            3,
            1,
            address(0),
            0,
            0,
            TradeData(
                Trade(TradeType.EXACT_IN_SINGLE, address(0), asset, 0.01469e18, 0, block.timestamp, abi.encode(uni)),
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
        lendingPool.flash(
            address(liquidator),
            asset,
            amount,
            abi.encode(params),
            address(liquidator),
            IERC7399Receiver.callback.selector
        );
    }

    function test_GhoLiquidation() public {
        vm.createSelectFork(MAINNET_RPC_URL, 20105851);
        address acct = makeAddr("account");
        address USDT = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
        deal(USDT, acct, 117e6, true);

        vm.startPrank(acct);
        notional.enablePrimeBorrow(true);
        BalanceAction[] memory balanceActions = new BalanceAction[](1);
        BalanceAction memory balanceAction =
            BalanceAction(DepositActionType.DepositUnderlyingAndMintNToken, 8, 117e6, 0, false, true);
        balanceActions[0] = balanceAction;
        IEIP20NonStandard(USDT).approve(address(notional), 117e6);
        notional.batchBalanceAction(acct, balanceActions);
        // Borrow GHO variable
        notional.withdraw(11, 80.2e8, true);
        vm.warp(block.timestamp + 86400 * 7);
        vm.stopPrank();

        FlashLiquidator _liquidator = new FlashLiquidator(
            notional,
            0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2,
            owner,
            address(tradingModule)
        );

        uint16[] memory c = new uint16[](2);
        c[0] = 8;
        c[1] = 11;
        vm.prank(owner);
        _liquidator.enableCurrencies(c);

        vm.prank(0x22341fB5D92D3d801144aA5A925F401A91418A05);
        tradingModule.setTokenPermissions(
            address(_liquidator),
            USDT,
            ITradingModule.TokenPermissions(true, uint32(1 << uint8(DexId.UNISWAP_V3)), 15)
        );

        address asset = 0x40D16FC0246aD3160Ccc09B8D0D3A2cD28aE6C2f;
        uint256 amount = 41e18;
        UniData memory uni = UniData(500);
        CollateralCurrencyLiquidation memory collateral = CollateralCurrencyLiquidation(
            acct,
            11, // GHO
            8, // USDT
            USDT,
            0,
            0,
            TradeData(
                Trade(TradeType.EXACT_IN_SINGLE, USDT, asset, 43030873, 0, block.timestamp, abi.encode(uni)),
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
        balancerFlashLender.flash(
            address(_liquidator),
            asset,
            amount,
            abi.encode(params),
            address(_liquidator),
            IERC7399Receiver.callback.selector
        );
    }
}