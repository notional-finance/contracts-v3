// SPDX-License-Identifier: MIT
pragma solidity =0.7.6;
pragma abicoder v2;

import {Test} from "forge-std/Test.sol";
import {NotionalProxy} from "../interfaces/notional/NotionalProxy.sol";

import {Constants} from "../contracts/global/Constants.sol";
import {TokenHandler} from "../contracts/internal/balances/TokenHandler.sol";
import {Deployments} from "../contracts/global/Deployments.sol";
import {IPrimeCashHoldingsOracle, OracleData} from "../interfaces/notional/IPrimeCashHoldingsOracle.sol";
import {IAavePool} from "../interfaces/aave/IAavePool.sol";
import {IERC20} from "../interfaces/IERC20.sol";
import {
    Token,
    PrimeRate,
    RebalancingTargetData,
    PrimeCashFactors
} from "../contracts/global/Types.sol";
import {Views} from "../contracts/external/Views.sol";
import {AccountAction} from "../contracts/external/actions/AccountAction.sol";
import {ExternalLending} from "../contracts/internal/balances/ExternalLending.sol";
import {CalculationViews} from "../contracts/external/CalculationViews.sol";
import {IRouter} from "../interfaces/notional/IRouter.sol";
import {NotionalTreasury} from "../interfaces/notional/NotionalTreasury.sol";
import {SafeInt256} from "../contracts/math/SafeInt256.sol";
import {SafeUint256} from "../contracts/math/SafeUint256.sol";

contract NotionalBaseTest is Test {
    using SafeUint256 for uint256;
    using SafeInt256 for int256;
    using TokenHandler for Token;

    address internal N_ADDRESS;
    address internal AAVE_LENDING_POOL;
    address internal POOL_DATA_PROVIDER;
    address internal REBALANCE_BOT;
    NotionalProxy internal NOTIONAL;

    string internal ARBITRUM_RPC_URL = vm.envString("ARBITRUM_RPC_URL");
    uint256 internal ARBITRUM_FORK_BLOCK = 150301701;
    // uint256 internal ARBITRUM_FORK_BLOCK = 154301701; // frax has problems on this block

    address internal ATOKEN;
    address internal UNDERLYING;
    uint16 internal CURRENCY_ID;

    uint256 internal RATE_PRECISION = uint256(Constants.RATE_PRECISION);

    address internal owner;

    function setUp() public virtual {
        vm.createSelectFork(ARBITRUM_RPC_URL, ARBITRUM_FORK_BLOCK);

        string memory json = vm.readFile("v3.arbitrum-one.json");
        N_ADDRESS = address(vm.parseJsonAddress(json, ".notional"));
        AAVE_LENDING_POOL = address(vm.parseJsonAddress(json, ".aaveLendingPool"));
        POOL_DATA_PROVIDER = address(vm.parseJsonAddress(json, ".aavePoolDataProvider"));
        REBALANCE_BOT = address(vm.parseJsonAddress(json, ".gelatoBot"));
        NOTIONAL = NotionalProxy(N_ADDRESS);

        owner = NOTIONAL.owner();
        labelDeployedContracts();
    }

    function getDeployedContracts() internal view returns (IRouter.DeployedContracts memory c) {
        IRouter r = IRouter(payable(address(NOTIONAL)));
        c.governance = r.GOVERNANCE();
        c.views = r.VIEWS();
        c.initializeMarket = r.INITIALIZE_MARKET();
        c.nTokenActions = r.NTOKEN_ACTIONS();
        c.batchAction = r.BATCH_ACTION();
        c.accountAction = r.ACCOUNT_ACTION();
        c.erc1155 = r.ERC1155();
        c.liquidateCurrency = r.LIQUIDATE_CURRENCY();
        c.liquidatefCash = r.LIQUIDATE_FCASH();
        c.treasury = r.TREASURY();
        c.calculationViews = r.CALCULATION_VIEWS();
        c.vaultAccountAction = r.VAULT_ACCOUNT_ACTION();
        c.vaultLiquidationAction = r.VAULT_LIQUIDATION_ACTION();
        c.vaultAccountHealth = r.VAULT_ACCOUNT_HEALTH();
    }

    function labelDeployedContracts() internal {
        IRouter.DeployedContracts memory c = getDeployedContracts();
        vm.label(address(NOTIONAL), "NotionalProxy");
        vm.label(NOTIONAL.getImplementation(), "NotionalRouter");
        vm.label(c.governance, "GOVERNANCE");
        vm.label(c.views, "VIEWS");
        vm.label(c.initializeMarket, "INITIALIZE_MARKET");
        vm.label(c.nTokenActions, "NTOKEN_ACTIONS");
        vm.label(c.batchAction, "BATCH_ACTION");
        vm.label(c.accountAction, "ACCOUNT_ACTION");
        vm.label(c.erc1155, "ERC1155");
        vm.label(c.liquidateCurrency, "LIQUIDATE_CURRENCY");
        vm.label(c.liquidatefCash, "LIQUIDATE_FCASH");
        vm.label(c.treasury, "TREASURY");
        vm.label(c.calculationViews, "CALCULATION_VIEWS");
        vm.label(c.vaultAccountAction, "VAULT_ACCOUNT_ACTION");
        vm.label(c.vaultLiquidationAction, "VAULT_LIQUIDATION_ACTION");
        vm.label(c.vaultAccountHealth, "VAULT_ACCOUNT_HEALTH");
        vm.label(0x82aF49447D8a07e3bd95BD0d56f35241523fBab1, "WETH");
        vm.label(0xB9bFBB35C2eD588a42f9Fd1120929c607B463192, "nBeaconProxy");
        vm.label(0x1F681977aF5392d9Ca5572FB394BC4D12939A6A9, "UpgradeableBeacon");
        vm.label(0x382173438e47b0c1F5dF9928F0e1f301b50Ed669, "PrimeCashProxy");
    }

    function upgradeTo(IRouter.DeployedContracts memory c) internal returns (IRouter r) {
        r = IRouter(deployCode("Router.sol", abi.encode(c)));
        vm.prank(NOTIONAL.owner());
        NOTIONAL.upgradeTo(address(r));

        vm.label(address(r), "NotionalRouter");
    }

    function _getRebalanceDelta(uint256 balance) internal pure returns (uint256 delta) {
        delta = balance * uint256(Constants.REBALANCING_UNDERLYING_DELTA_PERCENT) / uint256(Constants.RATE_PRECISION);
    }

    function _getActualRebalancingRate(uint16 currencyId, uint8 target) internal returns (uint256 _actualRate) {
        (PrimeRate memory pr, PrimeCashFactors memory factors) = NOTIONAL.accruePrimeInterest(currencyId);

        IPrimeCashHoldingsOracle oracle = IPrimeCashHoldingsOracle(NOTIONAL.getPrimeCashHoldingsOracle(currencyId));
        (, Token memory token) = NOTIONAL.getCurrency(currencyId);

        OracleData memory oracleData = oracle.getOracleData();
        RebalancingTargetData memory rebalancingTargetData = RebalancingTargetData(target, 120);
        uint256 targetAmount = ExternalLending.getTargetExternalLendingAmount(
            token,
            factors,
            rebalancingTargetData,
            oracleData,
            pr
        );
        uint256 totalValue = uint256(token.convertToExternal(int256(factors.lastTotalUnderlyingValue)));

        return targetAmount * RATE_PRECISION / totalValue;
    }

    function _setSingleTargetRateAndRebalance(uint16 currencyId, address target, uint8 targetRate) internal {
        vm.startPrank(owner);
        NotionalTreasury.RebalancingTargetConfig[] memory targets = new NotionalTreasury.RebalancingTargetConfig[](1);
        uint16 externalWithdrawThreshold = 120;
        targets[0] = NotionalTreasury.RebalancingTargetConfig(target, targetRate, externalWithdrawThreshold);
        NOTIONAL.setRebalancingTargets(currencyId, targets);
        skip(1);
        vm.stopPrank();
    }

    function _decimals(address token) internal view returns (uint8 decimals) {
        if (token == address(0)) {
            decimals = 18;
        } else {
            decimals = IERC20(token).decimals();
        }
    }

    function _actualBalanceOf(address token, address addr) internal view returns (uint256 balance) {
        if (token == address(0)) {
            balance = addr.balance;
        } else {
            balance = IERC20(token).balanceOf(addr);
        }
    }

    function _setCurrencyToTest(uint16 currencyId) public {
        CURRENCY_ID = currencyId;
        _deployAaveOracle(currencyId);

        ATOKEN = _getHoldings(CURRENCY_ID)[0];
        UNDERLYING = _getUnderlying(currencyId);
    }

    function _setCurrencyToTest(address underlying) public {
        UNDERLYING = underlying;
        CURRENCY_ID = _deployCurrency(UNDERLYING);
        ATOKEN = _getHoldings(CURRENCY_ID)[0];
    }

    function _deployCurrency(address underlying) internal virtual returns (uint16 currencyId) {
        currencyId = NOTIONAL.getCurrencyId(underlying);
        _deployAaveOracle(currencyId);
    }

    function _setCooldownForAllCurrencies(uint40 cooldown) internal {
        vm.startPrank(owner);

        uint16 maxCurrency = _getMaxCurrency();
        for (uint16 i = 1; i <= maxCurrency; i++) {
            NOTIONAL.setRebalancingCooldown(i, cooldown);
        }
        vm.stopPrank();
    }

    function _getUnderlying(uint16 currencyId) internal view returns (address underlyingToken) {
        underlyingToken = IPrimeCashHoldingsOracle(NOTIONAL.getPrimeCashHoldingsOracle(currencyId)).underlying();
    }

    function _getHoldings(uint16 currencyId) internal view returns (address[] memory holdings) {
        IPrimeCashHoldingsOracle oracle = IPrimeCashHoldingsOracle(NOTIONAL.getPrimeCashHoldingsOracle(currencyId));
        holdings = oracle.holdings();
    }

    function _deployAaveOracle(uint16 currencyId) internal {
        address underlyingToken = _getUnderlying(currencyId);
        address aToken;
        if (currencyId == 1) {
            aToken = IAavePool(AAVE_LENDING_POOL).getReserveData(address(Deployments.WETH)).aTokenAddress;
        } else {
            aToken = IAavePool(AAVE_LENDING_POOL).getReserveData(underlyingToken).aTokenAddress;
        }
        if (aToken == address(0)) {
            return;
        }

        IPrimeCashHoldingsOracle newOracle = IPrimeCashHoldingsOracle(deployCode(
            "AaveV3HoldingsOracle.sol",
            abi.encode(NOTIONAL, underlyingToken, AAVE_LENDING_POOL, aToken, POOL_DATA_PROVIDER))
        );

        vm.prank(NOTIONAL.owner());
        NOTIONAL.updatePrimeCashHoldingsOracle(currencyId, newOracle);
    }

    function _deployAllAaveOracles() internal {
        for (uint16 i = 1; i <= _getMaxCurrency(); i++) {
            _deployAaveOracle(i);
        }
    }

    function _deployTreasuryAndViews() internal {
        IRouter.DeployedContracts memory c = getDeployedContracts();
        c.treasury = deployCode("TreasuryAction.sol");
        c.calculationViews = address(new CalculationViews());
        c.views = address(new Views());
        c.accountAction = address(new AccountAction());

        upgradeTo(c);

        vm.startPrank(owner);

        NOTIONAL.setRebalancingBot(REBALANCE_BOT);
        vm.stopPrank();
    }

    function _toAddressArray(address token) internal pure returns (address[] memory tokens) {
        tokens = new address[](1);
        tokens[0] = token;
    }

    function _toUint16Array(uint16 currencyId) internal pure returns (uint16[] memory currencyIds) {
        currencyIds = new uint16[](1);
        currencyIds[0] = currencyId;
    }

    function _getStoredBalance(address token) internal view returns (uint256 balance) {
        address[] memory tokens = _toAddressArray(token);
        balance = NOTIONAL.getStoredTokenBalances(tokens)[0];
    }

    function _getMaxCurrency() internal view returns (uint16) {
        return NOTIONAL.getMaxCurrencyId();
    }
}