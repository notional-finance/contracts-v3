// SPDX-License-Identifier: BSUL-1.1
pragma solidity >=0.7.6;

interface IRewarder {
    function claimRewards(
        address account,
        uint256 nTokenBalanceBefore,
        uint256 nTokenBalanceAfter,
        uint256 totalSupply
    ) external;
}
