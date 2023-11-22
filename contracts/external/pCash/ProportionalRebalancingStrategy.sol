// SPDX-License-Identifier: BSUL-1.1
pragma solidity =0.7.6;
pragma abicoder v2;

import {NotionalProxy} from "../../../interfaces/notional/NotionalProxy.sol";
import {IPrimeCashHoldingsOracle} from "../../../interfaces/notional/IPrimeCashHoldingsOracle.sol";
import {IRebalancingStrategy, RebalancingData} from "../../../interfaces/notional/IRebalancingStrategy.sol";
import {Constants} from "../../global/Constants.sol";

contract ProportionalRebalancingStrategy is IRebalancingStrategy {
    NotionalProxy internal immutable NOTIONAL;

    constructor(NotionalProxy notional_) { NOTIONAL = notional_; }

    modifier onlyNotional() {
        require(msg.sender == address(NOTIONAL), "InvalidCaller");
        _;
    }

    function calculateRebalance(
        IPrimeCashHoldingsOracle oracle,
        uint8[] calldata rebalancingTargets
    ) external view override onlyNotional returns (RebalancingData memory rebalancingData) {
        address[] memory holdings = oracle.holdings();
        uint256[] memory values = oracle.holdingValuesInUnderlying();

        (
            uint256 totalValue,
            /* uint256 internalPrecision */
        ) = oracle.getTotalUnderlyingValueView();

        address[] memory redeemHoldings = new address[](holdings.length);
        uint256[] memory redeemAmounts = new uint256[](holdings.length);
        address[] memory depositHoldings = new address[](holdings.length);
        uint256[] memory depositAmounts = new uint256[](holdings.length);

        for (uint256 i; i < holdings.length; i++) {
            address holding = holdings[i];
            uint256 targetAmount = totalValue * rebalancingTargets[i] / uint256(Constants.PERCENTAGE_DECIMALS);
            uint256 currentAmount = values[i];

            redeemHoldings[i] = holding;
            depositHoldings[i] = holding;

            if (targetAmount < currentAmount) {
                redeemAmounts[i] = currentAmount - targetAmount;
            } else if (currentAmount < targetAmount) {
                depositAmounts[i] = targetAmount - currentAmount;
            }
        }

        rebalancingData.redeemData = oracle.getRedemptionCalldataForRebalancing(redeemHoldings, redeemAmounts);
        rebalancingData.depositData = oracle.getDepositCalldataForRebalancing(depositHoldings, depositAmounts);
    }
}