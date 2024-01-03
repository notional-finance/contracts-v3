// SPDX-License-Identifier: BSUL-1.1
pragma solidity >=0.7.6;

interface IRewarder {
    event RewardTransfer(address indexed rewardToken, address indexed account, uint256 amount);
    event RewardEmissionUpdate(uint256 emissionRatePerYear, uint256 endTime);

    function NTOKEN_ADDRESS() external returns(address);

    function CURRENCY_ID() external returns(uint16);

    function detached() external returns(bool);

    function claimRewards(
        address account,
        uint16 currencyId,
        uint256 nTokenBalanceBefore,
        uint256 nTokenBalanceAfter,
        uint256 totalSupply
    ) external;

    function getAccountRewardClaim(address account, uint32 blockTime) external returns (uint256);

    function getAccountRewardClaim(address account, uint256 nTokenBalanceAtDetach, bytes32[] calldata proof)
        external
        returns (uint256);

    function claimRewardsDirect(address account, uint256 nTokenBalanceAtDetach, bytes32[] calldata proof) external;

    function accumulatedRewardPerNToken() external returns (uint128);

    function lastAccumulatedTime() external returns (uint32);

    function emissionRatePerYear() external returns (uint128);

    function detach() external;
}
