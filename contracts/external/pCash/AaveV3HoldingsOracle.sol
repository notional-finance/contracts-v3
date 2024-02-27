// SPDX-License-Identifier: GPL-3.0-only
pragma solidity =0.7.6;
pragma abicoder v2;

import {UnderlyingHoldingsOracle} from "./UnderlyingHoldingsOracle.sol";
import {NotionalProxy} from "../../../interfaces/notional/NotionalProxy.sol";
import {DepositData, RedeemData, OracleData} from "../../../interfaces/notional/IPrimeCashHoldingsOracle.sol";
import {ILendingPool} from "../../../interfaces/aave/ILendingPool.sol";
import {IPoolDataProvider} from "../../../interfaces/aave/IPoolDataProvider.sol";
import {WETH9} from "../../../interfaces/WETH9.sol";
import {IERC20} from "../../../interfaces/IERC20.sol";
import {Deployments} from "../../global/Deployments.sol";
import {SafeUint256} from "../../math/SafeUint256.sol";

contract AaveV3HoldingsOracle is UnderlyingHoldingsOracle {
    using SafeUint256 for uint256;

    uint256 internal constant RAY = 1e27;
    uint256 internal constant HALF_RAY = 0.5e27;
    address internal immutable ASSET_TOKEN;
    address internal immutable LENDING_POOL;
    address internal immutable POOL_DATA_PROVIDER;

    uint256 public maxDeposit;

    constructor(NotionalProxy notional, address underlying, address lendingPool, address aToken, address poolDataProvider)
        UnderlyingHoldingsOracle(notional, underlying)
    {
        LENDING_POOL = lendingPool;
        ASSET_TOKEN = aToken;
        POOL_DATA_PROVIDER = poolDataProvider;
    }

    function setMaxAbsoluteDeposit(uint256 _maxDeposit) external {
        require(msg.sender == NOTIONAL.owner());
        maxDeposit = _maxDeposit;
    }

    function _holdings() internal view virtual override returns (address[] memory) {
        address[] memory result = new address[](1);
        result[0] = ASSET_TOKEN;
        return result;
    }

    function _holdingValuesInUnderlying() internal view virtual override returns (uint256[] memory) {
        address[] memory tokens = new address[](1);
        tokens[0] = ASSET_TOKEN;
        return NOTIONAL.getStoredTokenBalances(tokens);
    }

    function _getTotalUnderlyingValueView() internal view virtual override returns (uint256) {
        // Aave v3 asset tokens are in the same decimals and denomination as underlying and
        // therefore we can add them together directly.
        address[] memory tokens = new address[](2);
        tokens[0] = UNDERLYING_TOKEN;
        tokens[1] = ASSET_TOKEN;

        uint256[] memory balances = NOTIONAL.getStoredTokenBalances(tokens);
        return balances[0].add(balances[1]);
    }

    /// @notice Returns calldata for how to withdraw an amount
    function _getRedemptionCalldata(uint256 withdrawAmount)
        internal view virtual override returns (RedeemData[] memory data)
    {
        address underlyingToken = UNDERLYING_IS_ETH ? address(Deployments.WETH) : UNDERLYING_TOKEN;

        if (withdrawAmount == 0) return data;

        address[] memory targets = new address[](UNDERLYING_IS_ETH ? 2 : 1);
        bytes[] memory callData = new bytes[](UNDERLYING_IS_ETH ? 2 : 1);
        targets[0] = LENDING_POOL;
        callData[0] = abi.encodeWithSelector(
            ILendingPool.withdraw.selector, underlyingToken, withdrawAmount, address(NOTIONAL)
        );

        if (UNDERLYING_IS_ETH) {
            // Aave V3 returns WETH instead of native ETH so we have to unwrap it here
            targets[1] = address(Deployments.WETH);
            callData[1] = abi.encodeWithSelector(WETH9.withdraw.selector, withdrawAmount);
        }

        data = new RedeemData[](1);
        // Tokens with less than or equal to 8 decimals sometimes have off by 1 issues when depositing
        // into Aave V3. Aave returns one unit less than has been deposited. This adjustment is applied
        // to ensure that this unit of token is credited back to prime cash holders appropriately.
        uint8 rebasingTokenBalanceAdjustment = UNDERLYING_DECIMALS <= 8 ? 1 : 0;
        data[0] = RedeemData(
            targets, callData, withdrawAmount, ASSET_TOKEN, rebasingTokenBalanceAdjustment
        );

    }

    function _getRedemptionCalldataForRebalancing(address[] calldata holdings, uint256[] calldata withdrawAmounts)
        internal view virtual override returns (RedeemData[] memory redeemData)
    {
        require(holdings.length == 1 && holdings[0] == ASSET_TOKEN);
        return _getRedemptionCalldata(withdrawAmounts[0]);
    }

    function _getDepositCalldataForRebalancing(address[] calldata holdings, uint256[] calldata depositAmounts)
        internal view virtual override returns (DepositData[] memory data)
    {
        require(holdings.length == 1 && holdings[0] == ASSET_TOKEN);

        address from = address(NOTIONAL);
        uint256 depositUnderlyingAmount = depositAmounts[0];
        if (depositUnderlyingAmount == 0) return data;

        address[] memory targets = new address[](UNDERLYING_IS_ETH ? 3 : 2);
        bytes[] memory callData = new bytes[](UNDERLYING_IS_ETH ? 3 : 2);
        uint256[] memory msgValue = new uint256[](UNDERLYING_IS_ETH ? 3 : 2);

        if (UNDERLYING_IS_ETH) {
            targets[0] = address(Deployments.WETH);
            msgValue[0] = depositUnderlyingAmount;
            callData[0] = abi.encodeWithSelector(WETH9.deposit.selector, depositUnderlyingAmount);

            targets[1] = address(Deployments.WETH);
            callData[1] = abi.encodeWithSelector(IERC20.approve.selector, LENDING_POOL, depositUnderlyingAmount);

            targets[2] = LENDING_POOL;
            callData[2] = abi.encodeWithSelector(
                ILendingPool.deposit.selector,
                address(Deployments.WETH),
                depositUnderlyingAmount,
                from,
                0 // referralCode
            );
        } else {
            targets[0] = UNDERLYING_TOKEN;
            callData[0] = abi.encodeWithSelector(IERC20.approve.selector, LENDING_POOL, depositUnderlyingAmount);

            targets[1] = LENDING_POOL;
            callData[1] = abi.encodeWithSelector(
                ILendingPool.deposit.selector,
                UNDERLYING_TOKEN,
                depositUnderlyingAmount,
                from,
                0 // referralCode
            );
        }

        data = new DepositData[](1);

        // See a similar comment in getRedemptionCalldata
        uint8 rebasingTokenBalanceAdjustment = UNDERLYING_DECIMALS <= 8 ? 1 : 0;
        data[0] = DepositData(
            targets, callData, msgValue, depositUnderlyingAmount, ASSET_TOKEN, rebasingTokenBalanceAdjustment
        );
    }

    /// @notice Returns the oracle data during rebalancing
    function getOracleData() external view override returns (OracleData memory oracleData) {
        address underlying = UNDERLYING_IS_ETH ? address(Deployments.WETH) : UNDERLYING_TOKEN;

        (/* */, uint256 supplyCap) = IPoolDataProvider(POOL_DATA_PROVIDER).getReserveCaps(underlying);
        // Supply caps are returned as whole token values
        supplyCap = supplyCap * UNDERLYING_PRECISION;
        // This is the returned stored token balance of the aToken
        oracleData.currentExternalUnderlyingLend = _holdingValuesInUnderlying()[0];

        // Sets a cap on the total deposits
        if (0 < maxDeposit) {
            oracleData.maxExternalDeposit =  oracleData.currentExternalUnderlyingLend < maxDeposit ?
                maxDeposit - oracleData.currentExternalUnderlyingLend :
                0;
        } else if (supplyCap == 0) {
            // If supply cap is zero, that means there is no cap on the pool
            oracleData.maxExternalDeposit = type(uint256).max;
        } else {
            (/* */, uint256 accruedToTreasury, uint256 aTokenSupply,/* */,/* */,/* */,/* */,/* */,/* */,/* */,/* */,/* */) =
                IPoolDataProvider(POOL_DATA_PROVIDER).getReserveData(underlying);
            uint256 income = ILendingPool(LENDING_POOL).getReserveNormalizedIncome(underlying);

            // this calculation is not exactly correct since accruedToTreasury is not updated to current block
            // but it is a gas efficient way to approximately calculate current supply which is enough to
            // prevent system from hitting Aave pool supply cap
            uint256 currentSupply = (aTokenSupply + rayMul(accruedToTreasury, income)) * 1001 / 1000;
            if (supplyCap <= currentSupply) {
                oracleData.maxExternalDeposit = 0;
            } else {
                // underflow checked as consequence of if / else statement
                oracleData.maxExternalDeposit = supplyCap - currentSupply;
            }
        }

        oracleData.holding = ASSET_TOKEN;
        // The balance of the underlying on the aToken contract is the maximum that can be withdrawn
        oracleData.externalUnderlyingAvailableForWithdraw = IERC20(underlying).balanceOf(ASSET_TOKEN);
    }

    function rayMul(uint256 a, uint256 b) private pure returns (uint256 c) {
        // to avoid overflow, a <= (type(uint256).max - HALF_RAY) / b
        assembly {
            if iszero(or(iszero(b), iszero(gt(a, div(sub(not(0), HALF_RAY), b))))) {
                revert(0, 0)
            }

            c := div(add(mul(a, b), HALF_RAY), RAY)
        }
    }
}