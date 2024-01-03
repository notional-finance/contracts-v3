// SPDX-License-Identifier: BSUL-1.1
pragma solidity =0.7.6;
pragma abicoder v2;

import {UnderlyingHoldingsOracle} from "./UnderlyingHoldingsOracle.sol";
import {CErc20Interface} from "../../../interfaces/compound/CErc20Interface.sol";
import {SafeUint256} from "../../math/SafeUint256.sol";
import {SafeInt256} from "../../math/SafeInt256.sol";
import {NotionalProxy} from "../../../interfaces/notional/NotionalProxy.sol";
import {AssetRateAdapter} from "../../../interfaces/notional/AssetRateAdapter.sol";
import {DepositData, RedeemData} from "../../../interfaces/notional/IPrimeCashHoldingsOracle.sol";

struct CompoundV2DeploymentParams {
    NotionalProxy notional;
    address underlying;
    address cToken;
    address cTokenRateAdapter;
}

contract CompoundV2HoldingsOracle is UnderlyingHoldingsOracle {
    using SafeUint256 for uint256;
    using SafeInt256 for int256;

    uint8 private constant NUM_ASSET_TOKENS = 1;
    address internal immutable COMPOUND_ASSET_TOKEN;
    address internal immutable COMPOUND_RATE_ADAPTER;
    uint256 private immutable RATE_ADAPTER_PRECISION;

    constructor(CompoundV2DeploymentParams memory params) 
        UnderlyingHoldingsOracle(params.notional, params.underlying) {
        COMPOUND_ASSET_TOKEN = params.cToken;
        COMPOUND_RATE_ADAPTER = params.cTokenRateAdapter;
        RATE_ADAPTER_PRECISION = 10**AssetRateAdapter(params.cTokenRateAdapter).decimals();
    }

    /// @notice Returns a list of the various holdings for the prime cash
    /// currency
    function _holdings() internal view virtual override returns (address[] memory) {
        address[] memory result = new address[](NUM_ASSET_TOKENS);
        result[0] = COMPOUND_ASSET_TOKEN;
        return result;
    }

    function _holdingValuesInUnderlying() internal view virtual override returns (uint256[] memory) {
        uint256[] memory result = new uint256[](NUM_ASSET_TOKENS);
        address[] memory tokens = new address[](NUM_ASSET_TOKENS);
        tokens[0] = COMPOUND_ASSET_TOKEN;
        result[0] = _compUnderlyingValue(NOTIONAL.getStoredTokenBalances(tokens)[0]);
        return result;
    }

    function _getTotalUnderlyingValueView() internal view virtual override returns (uint256) {
        // NUM_ASSET_TOKENS + underlying
        address[] memory tokens = new address[](NUM_ASSET_TOKENS + 1);
        tokens[0] = UNDERLYING_TOKEN;
        tokens[1] = COMPOUND_ASSET_TOKEN;

        uint256[] memory balances = NOTIONAL.getStoredTokenBalances(tokens);
        return _compUnderlyingValue(balances[1]).add(balances[0]);
    }

    function _compUnderlyingValue(uint256 assetBalance) internal view returns (uint256) {
        return assetBalance
            .mul(AssetRateAdapter(COMPOUND_RATE_ADAPTER).getExchangeRateView().toUint())
            .div(RATE_ADAPTER_PRECISION);
    } 

    /// @notice Returns calldata for how to withdraw an amount
    function _getRedemptionCalldata(
        uint256 withdrawAmount
    ) internal view virtual override returns (RedeemData[] memory redeemData) {
        if (withdrawAmount == 0) return redeemData;

        address[] memory targets = new address[](1);
        bytes[] memory callData = new bytes[](1);
        targets[0] = COMPOUND_ASSET_TOKEN;
        callData[0] = abi.encodeWithSelector(CErc20Interface.redeemUnderlying.selector, withdrawAmount);

        redeemData = new RedeemData[](1);
        redeemData[0] = RedeemData(targets, callData, withdrawAmount, COMPOUND_ASSET_TOKEN, 0);
    }

    function _getRedemptionCalldataForRebalancing(
        address[] calldata holdings, 
        uint256[] calldata withdrawAmounts
    ) internal view virtual override returns (RedeemData[] memory redeemData) {
        require(holdings.length == NUM_ASSET_TOKENS && holdings[0] == COMPOUND_ASSET_TOKEN);
        return _getRedemptionCalldata(withdrawAmounts[0]);
    }

    function _getDepositCalldataForRebalancing(
        address[] calldata holdings, 
        uint256[] calldata depositAmounts
    ) internal view virtual override returns (DepositData[] memory depositData) {
        // Not allowed to deposit into Compound V2
        revert("Unimplemented");
    }
}