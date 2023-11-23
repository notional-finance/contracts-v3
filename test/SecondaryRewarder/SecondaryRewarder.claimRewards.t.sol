// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;
pragma abicoder v2;

import {console2 as console} from "forge-std/console2.sol";

import {SecondaryRewarderSetupTest} from "./SecondaryRewarderSetupTest.sol";
import {Router} from "../../contracts/external/Router.sol";
import {TreasuryAction} from "../../contracts/external/actions/TreasuryAction.sol";
import {IERC20} from "../../interfaces/IERC20.sol";
import {BalanceAction, DepositActionType} from "../../contracts/global/Types.sol";
import {SecondaryRewarder} from "../../contracts/internal/balances/SecondaryRewarder.sol";
import {Constants} from "../../contracts/global/Constants.sol";
import {SafeInt256} from "../../contracts/math/SafeInt256.sol";
import {SafeUint256} from "../../contracts/math/SafeUint256.sol";

contract ClaimRewards is SecondaryRewarderSetupTest {
    using SafeUint256 for uint256;
    using SafeInt256 for int256;

    SecondaryRewarder private rewarder;
    IERC20 private cbEth = IERC20(0x1DEBd73E752bEaF79865Fd6446b0c970EaE7732f);
    address private owner;
    uint16 private CURRENCY_ID;
    address private REWARD_TOKEN;
    address private NTOKEN;

    struct AccountsData {
        address account;
        uint16 initialShare;
    }

    AccountsData[3] private initialAccounts;
    uint32 private emissionRatePerYear;
    uint256 private incentiveTokenDecimals;
    uint32 private endTime;

    function _getCurrencyAndRewardToken() internal virtual returns (uint16, address) {
        return (9, 0x912CE59144191C1204E64559FE8253a0e49E6548);
    }

    function _depositAndMintNToken(address account, uint256 amount) private {
        BalanceAction[] memory balanceActions = new BalanceAction[](1);
        BalanceAction memory balanceAction =
            BalanceAction(DepositActionType.DepositUnderlyingAndMintNToken, CURRENCY_ID, amount, 0, false, true);
        balanceActions[0] = balanceAction;

        vm.startPrank(account);
        cbEth.approve(address(NOTIONAL), amount);
        NOTIONAL.batchBalanceAction(account, balanceActions);
        vm.stopPrank();
    }

    function _initializeCbEthMarket() private {
        address fundingAccount = 0x7d7935EDd4b6cDB5f34B0E1cCEAF85a3C4A11254;
        _depositAndMintNToken(fundingAccount, 0.05e18);

        vm.startPrank(fundingAccount);
        NOTIONAL.initializeMarkets(CURRENCY_ID, true);
        vm.stopPrank();
    }

    function _depositWithInitialAccounts() private {
        uint256 totalInitialDeposit = 6e20;
        initialAccounts[0] = AccountsData(vm.addr(12321), 10);
        initialAccounts[1] = AccountsData(vm.addr(12322), 40);
        initialAccounts[2] = AccountsData(vm.addr(12323), 50);

        for (uint256 i = 0; i < initialAccounts.length; i++) {
            address account = initialAccounts[i].account;
            uint256 amount = totalInitialDeposit * initialAccounts[i].initialShare / 100;
            if (i + 1 == initialAccounts.length) {
                amount -= 0.05e18;
            }
            deal(address(cbEth), account, amount);
            _depositAndMintNToken(account, amount);
        }
    }

    function setUp() public {
        (uint16 currencyId, address rewardToken) = _getCurrencyAndRewardToken();
        CURRENCY_ID = currencyId;
        REWARD_TOKEN = rewardToken;

        forkAfterCbEthDeploy();
        _initializeCbEthMarket();
        _depositWithInitialAccounts();

        NTOKEN = NOTIONAL.nTokenAddress(currencyId);
        emissionRatePerYear = 2e5;
        incentiveTokenDecimals = 10 ** IERC20(rewardToken).decimals();
        endTime = uint32(block.timestamp + Constants.YEAR);
        rewarder = new SecondaryRewarder(
            NOTIONAL,
            currencyId,
            IERC20(rewardToken),
            emissionRatePerYear,
            endTime
        );
        owner = NOTIONAL.owner();

        Router.DeployedContracts memory c = getDeployedContracts();
        c.treasury = address(new TreasuryAction(TreasuryAction(c.treasury).COMPTROLLER()));
        upgradeTo(c);

        vm.prank(owner);
        NOTIONAL.setSecondaryIncentiveRewarder(currencyId, rewarder);
    }

    function test_getAccountRewardClaim_ShouldBeZeroAtStartOfIncentivePeriod() public {
        for (uint256 i = 0; i < initialAccounts.length; i++) {
            uint256 reward = rewarder.getAccountRewardClaim(initialAccounts[i].account, uint32(block.timestamp));
            assertTrue(reward == 0);
        }
    }

    function test_getAccountRewardClaim_ShouldNotBeZeroAfterSomeTime(uint32 timeToSkip) public {
        timeToSkip = uint32(bound(timeToSkip, 0, uint256(type(uint32).max / 10)));
        uint40 starTime = uint40(block.timestamp);

        skip(timeToSkip);

        // forgefmt: disable-next-item
        uint256 totalGeneratedIncentive = uint256(SafeInt256.min(timeToSkip, endTime - starTime))
            .mul(emissionRatePerYear)
            .mul(Constants.INCENTIVE_ACCUMULATION_PRECISION)
            .div(Constants.YEAR);

        for (uint256 i = 0; i < initialAccounts.length - 1; i++) {
            // forgefmt: disable-next-item
            uint256 predictedReward = totalGeneratedIncentive
                .mul(initialAccounts[i].initialShare)
                .div(100)
                .div(Constants.INCENTIVE_ACCUMULATION_PRECISION);
            uint256 reward = rewarder.getAccountRewardClaim(initialAccounts[i].account, uint32(block.timestamp));

            assertEq(reward / incentiveTokenDecimals, predictedReward, vm.toString(i));
        }
    }
}
