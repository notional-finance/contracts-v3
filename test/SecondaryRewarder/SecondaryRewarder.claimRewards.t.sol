// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;
pragma abicoder v2;

import {console2 as console} from "forge-std/console2.sol";

import {SecondaryRewarderSetupTest} from "./SecondaryRewarderSetupTest.sol";
import {Router} from "../../contracts/external/Router.sol";
import {BatchAction} from "../../contracts/external/actions/BatchAction.sol";
import {nTokenAction} from "../../contracts/external/actions/nTokenAction.sol";
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

    AccountsData[6] private initialAccounts;
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

        deal(address(cbEth), account, amount);
        vm.startPrank(account);
        cbEth.approve(address(NOTIONAL), amount);
        NOTIONAL.batchBalanceAction(account, balanceActions);
        vm.stopPrank();
    }

    function _redeemNToken(address account, uint256 amount) private {
        BalanceAction[] memory balanceActions = new BalanceAction[](1);
        BalanceAction memory balanceAction =
            BalanceAction(DepositActionType.RedeemNToken, CURRENCY_ID, amount, 0, false, true);
        balanceActions[0] = balanceAction;

        vm.startPrank(account);
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
        initialAccounts[0] = AccountsData(vm.addr(12320), 10);
        initialAccounts[1] = AccountsData(vm.addr(12321), 40);
        initialAccounts[2] = AccountsData(vm.addr(12322), 15);
        initialAccounts[3] = AccountsData(vm.addr(12323), 25);
        initialAccounts[4] = AccountsData(vm.addr(12324), 5);
        // don't test this one, it will just be used to "round" the 0.05e18 deposited at initialization
        initialAccounts[5] = AccountsData(vm.addr(12325), 5);

        for (uint256 i = 0; i < initialAccounts.length; i++) {
            address account = initialAccounts[i].account;
            uint256 amount = totalInitialDeposit * initialAccounts[i].initialShare / 100;
            if (i + 1 == initialAccounts.length) {
                amount -= 0.05e18;
            }
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
        deal(REWARD_TOKEN, address(rewarder), emissionRatePerYear * incentiveTokenDecimals);
        owner = NOTIONAL.owner();

        Router.DeployedContracts memory c = getDeployedContracts();
        c.batchAction = address(new BatchAction());
        c.treasury = address(new TreasuryAction(TreasuryAction(c.treasury).COMPTROLLER()));
        c.nTokenActions = address(new nTokenAction());
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

            assertApproxEqAbs(reward / incentiveTokenDecimals, predictedReward, 1, vm.toString(i));
        }
    }

    function test_claimReward_ShouldBeAbleToClaimIncentivesManual(uint32 timeToSkip) public {
        timeToSkip = uint32(bound(timeToSkip, 1000, uint256(type(uint32).max / 10)));

        skip(timeToSkip);

        for (uint256 i = 0; i < initialAccounts.length - 1; i++) {
            uint256 reward = rewarder.getAccountRewardClaim(initialAccounts[i].account, uint32(block.timestamp));

            assertEq(IERC20(REWARD_TOKEN).balanceOf(initialAccounts[i].account), 0);

            vm.prank(initialAccounts[i].account);
            NOTIONAL.nTokenClaimIncentives();

            assertEq(IERC20(REWARD_TOKEN).balanceOf(initialAccounts[i].account), reward);
        }
    }

    function test_claimReward_SequentialManualClaims() public {
        uint32 timeToSkip = 1 weeks;

        skip(timeToSkip);

        for (uint256 i = 0; i < initialAccounts.length - 1; i++) {
            uint256 reward = rewarder.getAccountRewardClaim(initialAccounts[i].account, uint32(block.timestamp));
            assertTrue(reward != 0);

            assertEq(IERC20(REWARD_TOKEN).balanceOf(initialAccounts[i].account), 0);

            vm.prank(initialAccounts[i].account);
            NOTIONAL.nTokenClaimIncentives();

            assertEq(IERC20(REWARD_TOKEN).balanceOf(initialAccounts[i].account), reward);
        }
        // second skip
        skip(2 weeks);

        for (uint256 i = 0; i < initialAccounts.length - 1; i++) {
            uint256 reward = rewarder.getAccountRewardClaim(initialAccounts[i].account, uint32(block.timestamp));
            assertTrue(reward != 0);

            uint256 prevBal = IERC20(REWARD_TOKEN).balanceOf(initialAccounts[i].account);

            vm.prank(initialAccounts[i].account);
            NOTIONAL.nTokenClaimIncentives();

            uint256 newBal = IERC20(REWARD_TOKEN).balanceOf(initialAccounts[i].account);

            assertEq(newBal, prevBal + reward);
        }
    }

    function test_claimReward_TransferOfNTokenShouldTriggerClaim(uint32 timeToSkip) public {
        timeToSkip = uint32(bound(timeToSkip, 1000, uint256(type(uint32).max / 10)));

        skip(timeToSkip);

        for (uint256 i = 0; i < initialAccounts.length - 1; i++) {
            uint256 reward = rewarder.getAccountRewardClaim(initialAccounts[i].account, uint32(block.timestamp));

            assertEq(IERC20(REWARD_TOKEN).balanceOf(initialAccounts[i].account), 0);

            // transfer should trigger claim
            vm.prank(initialAccounts[i].account);
            IERC20(NTOKEN).transfer(vm.addr(111111), 100);
            // trigger claim
            // _depositAndMintNToken(initialAccounts[i].account, 100);

            assertEq(IERC20(REWARD_TOKEN).balanceOf(initialAccounts[i].account), reward);
        }
    }

    function test_claimReward_ShouldClaimFullAmountAfterTheEnd() public {
        uint32 afterIncentivePeriod = endTime - uint32(block.timestamp) + 1 weeks;
        // forgefmt: disable-next-item
        uint256 totalIncentives = (endTime - block.timestamp)
                .mul(emissionRatePerYear)
                .div(Constants.YEAR);

        // should claim full amount
        skip(afterIncentivePeriod);

        for (uint256 i = 0; i < initialAccounts.length - 1; i++) {
            // forgefmt: disable-next-item
            uint256 reward = totalIncentives
                .mul(initialAccounts[i].initialShare)
                .div(100);
            assertTrue(reward != 0);

            uint256 prevBal = IERC20(REWARD_TOKEN).balanceOf(initialAccounts[i].account);
            assertEq(prevBal, 0);

            vm.prank(initialAccounts[i].account);
            NOTIONAL.nTokenClaimIncentives();

            uint256 newBal = IERC20(REWARD_TOKEN).balanceOf(initialAccounts[i].account);
            assertApproxEqAbs(newBal.div(incentiveTokenDecimals), reward, 1);
        }
        // second skip, should claim 0
        skip(1 weeks);

        for (uint256 i = 0; i < initialAccounts.length - 1; i++) {
            uint256 reward = rewarder.getAccountRewardClaim(initialAccounts[i].account, uint32(block.timestamp));
            assertTrue(reward == 0);

            uint256 prevBal = IERC20(REWARD_TOKEN).balanceOf(initialAccounts[i].account);

            vm.prank(initialAccounts[i].account);
            NOTIONAL.nTokenClaimIncentives();

            uint256 newBal = IERC20(REWARD_TOKEN).balanceOf(initialAccounts[i].account);

            assertEq(newBal, prevBal);
        }
    }

    // TODO: ???
    // function test_claimReward_MintOfNTokenShouldTriggerClaim(uint32 timeToSkip) public {
    //     timeToSkip = uint32(bound(timeToSkip, 1000, uint256(type(uint32).max / 10)));
    //
    //     skip(timeToSkip);
    //
    //     for (uint256 i = 0; i < initialAccounts.length - 1; i++) {
    //         uint256 reward = rewarder.getAccountRewardClaim(initialAccounts[i].account, uint32(block.timestamp));
    //
    //         assertEq(IERC20(REWARD_TOKEN).balanceOf(initialAccounts[i].account), 0);
    //
    //         uint256 prevNTokenBal = IERC20(NTOKEN).balanceOf(initialAccounts[i].account);
    //         // trigger claim
    //         _depositAndMintNToken(initialAccounts[i].account, 1e18);
    //
    //         uint256 newNTokenBal = IERC20(NTOKEN).balanceOf(initialAccounts[i].account);
    //
    //         assertLt(prevNTokenBal, newNTokenBal);
    //
    //         assertEq(IERC20(REWARD_TOKEN).balanceOf(initialAccounts[i].account), reward);
    //
    //     }
    // }
}
