// SPDX-License-Identifier: BSUL-1.1
pragma solidity >=0.7.6;

interface IRewarder {
    function claimRewards(
        address account,
        uint16 currencyId,
        uint256 nTokenBalanceBefore,
        uint256 nTokenBalanceAfter,
        uint256 totalSupply
    ) external;

    function getAccountRewardClaim(uint32 blockTime) external returns (uint256);

    function accumulatedRewardPerNToken() external returns(uint128);

    function lastAccumulatedTime() external returns(uint32);

    function emissionRatePerYear() external returns(uint32);
}
