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

    address internal immutable ASSET_TOKEN;
    address internal immutable LENDING_POOL;
    address internal immutable POOL_DATA_PROVIDER;

    constructor(NotionalProxy notional, address underlying, address lendingPool, address aToken, address poolDataProvider)
        UnderlyingHoldingsOracle(notional, underlying)
    {
        LENDING_POOL = lendingPool;
        ASSET_TOKEN = aToken;
        POOL_DATA_PROVIDER = poolDataProvider;
    }

    function _holdings() internal view virtual override returns (address[] memory) {
        address[] memory result = new address[](1);
        result[0] = ASSET_TOKEN;
        return result;
    }

    function _holdingValuesInUnderlying() internal view virtual override returns (uint256[] memory) {
        uint256[] memory result = new uint256[](1);
        address[] memory tokens = new address[](1);
        tokens[0] = ASSET_TOKEN;
        result[0] = NOTIONAL.getStoredTokenBalances(tokens)[0];
        return result;
    }

    function _getTotalUnderlyingValueView() internal view virtual override returns (uint256) {
        // asset token + underlying
        address[] memory tokens = new address[](2);
        tokens[0] = UNDERLYING_TOKEN;
        tokens[1] = ASSET_TOKEN;

        uint256[] memory balances = NOTIONAL.getStoredTokenBalances(tokens);
        return balances[0].add(balances[1]);
    }

    /// @notice Returns calldata for how to withdraw an amount
    function _getRedemptionCalldata(uint256 withdrawAmount)
        internal
        view
        virtual
        override
        returns (RedeemData[] memory data)
    {
        address underlyingToken = UNDERLYING_IS_ETH ? address(Deployments.WETH) : UNDERLYING_TOKEN;

        if (withdrawAmount == 0) {
            return data;
        }

        address[] memory targets = new address[](UNDERLYING_IS_ETH ? 2 : 1);
        bytes[] memory callData = new bytes[](UNDERLYING_IS_ETH ? 2 : 1);
        targets[0] = LENDING_POOL;
        callData[0] =
            abi.encodeWithSelector(ILendingPool.withdraw.selector, underlyingToken, withdrawAmount, address(NOTIONAL));

        if (UNDERLYING_IS_ETH) {
            targets[1] = address(Deployments.WETH);
            callData[1] = abi.encodeWithSelector(WETH9.withdraw.selector, withdrawAmount);
        }

        data = new RedeemData[](1);
        // fix for issue with Aave returning 1 less unit of asset token than expected
        // this fix relies on the Aave 1 : 1 exchange rate between underlying and asset token
        uint8 assetTokenBalanceAdjustment = UNDERLYING_DECIMALS <= 8 ? 1 : 0;
        data[0] = RedeemData(targets, callData, withdrawAmount, ASSET_TOKEN,assetTokenBalanceAdjustment);

    }

    function _getRedemptionCalldataForRebalancing(address[] calldata holdings, uint256[] calldata withdrawAmounts)
        internal
        view
        virtual
        override
        returns (RedeemData[] memory redeemData)
    {
        require(holdings.length == 1 && holdings[0] == ASSET_TOKEN);
        return _getRedemptionCalldata(withdrawAmounts[0]);
    }

    function _getDepositCalldataForRebalancing(address[] calldata holdings, uint256[] calldata depositAmounts)
        internal
        view
        virtual
        override
        returns (DepositData[] memory data)
    {
        require(holdings.length == 1 && holdings[0] == ASSET_TOKEN);

        address from = address(NOTIONAL);
        uint256 depositUnderlyingAmount = depositAmounts[0];
        if (depositUnderlyingAmount == 0) {
            return data;
        }

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

        // fix for issue with Aave returning 1 less unit of asset token than expected
        // this fix relies on the Aave 1 : 1 exchange rate between underlying and asset token
        uint8 assetTokenBalanceAdjustment = UNDERLYING_DECIMALS <= 8 ? 1 : 0;
        data[0] = DepositData(
            targets,
            callData,
            msgValue,
            depositUnderlyingAmount,
            ASSET_TOKEN,
            assetTokenBalanceAdjustment
        );
    }


    function getOracleData() external view override returns (OracleData memory oracleData)
    {
        address underlying = UNDERLYING_IS_ETH ? address(Deployments.WETH) : UNDERLYING_TOKEN;

        (, uint256 totalSupply) = IPoolDataProvider(POOL_DATA_PROVIDER).getReserveCaps(underlying);
        uint256 aTokenSupply = IPoolDataProvider(POOL_DATA_PROVIDER).getATokenTotalSupply(underlying);
        totalSupply = totalSupply * UNDERLYING_PRECISION;

        // if aave total supply is zero, that means there is no cap on the pool
        if (totalSupply == 0) {
            oracleData.maxExternalDeposit = type(uint256).max;
        } else if (totalSupply <= aTokenSupply) {
            oracleData.maxExternalDeposit = 0;
        } else {
            oracleData.maxExternalDeposit = totalSupply  - aTokenSupply;
        }

        oracleData.holding = ASSET_TOKEN;
        oracleData.externalUnderlyingAvailableForWithdraw = IERC20(underlying).balanceOf(ASSET_TOKEN);
        oracleData.currentExternalUnderlyingLend = _holdingValuesInUnderlying()[0];
    }
}