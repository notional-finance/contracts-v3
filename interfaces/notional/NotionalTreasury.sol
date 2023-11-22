// SPDX-License-Identifier: BSUL-1.1
pragma solidity >=0.7.6;
pragma abicoder v2;

import {IRewarder} from "./IRewarder.sol";

interface NotionalTreasury {
    event UpdateIncentiveEmissionRate(uint16 currencyId, uint32 newEmissionRate);
    event UpdateSecondaryIncentiveRewarder(uint16 indexed currencyId, address rewarder);

    struct RebalancingTargetConfig {
        address holding;
        uint8 targetUtilization;
        uint16 externalWithdrawThreshold;
    }

    /// @notice Emitted when reserve balance is updated
    event ReserveBalanceUpdated(uint16 indexed currencyId, int256 newBalance);
    /// @notice Emitted when reserve balance is harvested
    event ExcessReserveBalanceHarvested(uint16 indexed currencyId, int256 harvestAmount);
    /// @dev Emitted when treasury manager is updated
    event TreasuryManagerChanged(address indexed previousManager, address indexed newManager);
    /// @dev Emitted when reserve buffer value is updated
    event ReserveBufferUpdated(uint16 currencyId, uint256 bufferAmount);

    event RebalancingTargetsUpdated(uint16 currencyId, RebalancingTargetConfig[] targets);

    event RebalancingCooldownUpdated(uint16 currencyId, uint40 cooldownTimeInSeconds);

    event CurrencyRebalanced(uint16 currencyId, uint256 supplyFactor, uint256 annualizedInterestRate);

    /// @notice Emitted when the interest accrued on asset deposits is harvested 
    event AssetInterestHarvested(uint16 indexed currencyId, address assetToken, uint256 harvestAmount);

    function transferReserveToTreasury(uint16[] calldata currencies) external returns (uint256[] memory);

    function harvestAssetInterest(uint16[] calldata currencies) external;

    function setTreasuryManager(address manager) external;

    function setRebalancingBot(address _rebalancingBot) external;

    function setReserveBuffer(uint16 currencyId, uint256 amount) external;

    function setReserveCashBalance(uint16 currencyId, int256 reserveBalance) external;

    function setRebalancingTargets(uint16 currencyId, RebalancingTargetConfig[] calldata targets) external;

    function setRebalancingCooldown(uint16 currencyId, uint40 cooldownTimeInSeconds) external;

    function checkRebalance() external returns (bool canExec, bytes memory execPayload);

    function rebalance(uint16[] calldata currencyId) external;

    function updateIncentiveEmissionRate(uint16 currencyId, uint32 newEmissionRate) external;

    function setSecondaryIncentiveRewarder(uint16 currencyId, IRewarder rewarder) external;
}