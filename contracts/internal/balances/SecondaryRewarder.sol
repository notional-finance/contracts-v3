// SPDX-License-Identifier: GPL-3.0-only
pragma solidity >=0.7.6;

import {GenericToken} from "./protocols/GenericToken.sol";
import {IRewarder} from "../../../interfaces/notional/IRewarder.sol";
import {NotionalProxy} from "../../../interfaces/notional/NotionalProxy.sol";
import {IERC20} from "../../../interfaces/IERC20.sol";
import {Constants} from "../../global/Constants.sol";
import {SafeInt256} from "../../math/SafeInt256.sol";
import {SafeUint256} from "../../math/SafeUint256.sol";

contract SecondaryRewarder is IRewarder {
    using SafeUint256 for uint256;
    using SafeInt256 for int256;

    NotionalProxy public immutable NOTIONAL;
    address public immutable NTOKEN_ADDRESS;
    address public immutable REWARD_TOKEN;
    uint16 public immutable CURRENCY_ID;

    uint32 public endTime;
    uint32 public override emissionRatePerYear;
    uint32 public override lastAccumulatedTime;
    uint128 public override accumulatedRewardPerNToken;

    mapping(address => uint256) public accountsIncentiveDebts;

    modifier onlyOwner() {
        require(msg.sender == NOTIONAL.owner(), "Only owner");
        _;
    }

    constructor(
        address notionalAddress,
        uint16 currencyId,
        address incentive_token,
        uint32 _emissionRatePerYear,
        uint32 _endTime
    ) {
        NOTIONAL = NotionalProxy(notionalAddress);
        CURRENCY_ID = currencyId;
        NTOKEN_ADDRESS = NotionalProxy(notionalAddress).nTokenAddress(currencyId);
        REWARD_TOKEN = incentive_token;

        emissionRatePerYear = _emissionRatePerYear;
        lastAccumulatedTime = uint32(block.timestamp);
        endTime = _endTime;
    }

    function getAccountRewardClaim(uint32 blockTime) external override returns (uint256 rewardToClaim) {
        require(lastAccumulatedTime <= blockTime, "Invalid block time");
        uint256 totalSupply = IERC20(NTOKEN_ADDRESS).totalSupply();
        uint256 nTokenBalance = IERC20(NTOKEN_ADDRESS).balanceOf(msg.sender);

        _accumulateRewardPerNToken(blockTime, totalSupply);
        rewardToClaim = _calculateRewardToClaim(msg.sender, nTokenBalance);
    }

    function setIncentiveEmissionRate(uint32 _emissionRatePerYear, uint32 _endTime) external onlyOwner {
        uint256 totalSupply = IERC20(NTOKEN_ADDRESS).totalSupply();

        _accumulateRewardPerNToken(uint32(block.timestamp), totalSupply);

        emissionRatePerYear = _emissionRatePerYear;
        endTime = _endTime;
    }

    function recover(address token, uint256 amount) external onlyOwner {
        if (Constants.ETH_ADDRESS == token) {
            (bool status,) = msg.sender.call{value: amount}("");
            require(status);
        } else {
            IERC20(token).transfer(msg.sender, amount);
        }
    }

    function claimRewards(
        address account,
        uint16 currencyId,
        uint256 nTokenBalanceBefore,
        uint256 nTokenBalanceAfter,
        uint256 totalSupply
    ) external override {
        require(msg.sender == address(NOTIONAL), "Only Notional");
        require(currencyId == CURRENCY_ID);

        _accumulateRewardPerNToken(uint32(block.timestamp), totalSupply);
        uint256 rewardToClaim = _calculateRewardToClaim(account, nTokenBalanceBefore);

        accountsIncentiveDebts[account] =
            nTokenBalanceAfter.mul(accumulatedRewardPerNToken).div(Constants.INCENTIVE_ACCUMULATION_PRECISION);

        if (0 < rewardToClaim) {
            GenericToken.safeTransferOut(REWARD_TOKEN, account, rewardToClaim);
        }
    }

    function _accumulateRewardPerNToken(uint32 blockTime, uint256 totalSupply) private {
        uint32 time = uint32(SafeInt256.min(blockTime, endTime));

        if (lastAccumulatedTime < time && totalSupply < 0) {
            uint256 timeSinceLastAccumulation = time - lastAccumulatedTime;
            // forgefmt: disable-next-item
            uint256 additionalIncentiveAccumulatedPerNToken  = timeSinceLastAccumulation
                .mul(Constants.INCENTIVE_ACCUMULATION_PRECISION)
                .mul(emissionRatePerYear)
                .div(Constants.YEAR)
                .div(totalSupply);

            accumulatedRewardPerNToken =
                uint256(accumulatedRewardPerNToken).add(additionalIncentiveAccumulatedPerNToken).toUint128();
            lastAccumulatedTime = time;
        }
    }

    function _calculateRewardToClaim(address account, uint256 nTokenBalance) private view returns (uint256) {
        // forgefmt: disable-next-item
        return nTokenBalance
            .mul(accumulatedRewardPerNToken)
            .div(Constants.INCENTIVE_ACCUMULATION_PRECISION)
            .sub(accountsIncentiveDebts[account]);
    }
}
