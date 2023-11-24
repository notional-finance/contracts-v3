// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;
pragma abicoder v2;

import {SecondaryRewarderSetupTest} from "./SecondaryRewarderSetupTest.sol";
import {Router} from "../../contracts/external/Router.sol";
import {BatchAction} from "../../contracts/external/actions/BatchAction.sol";
import {nTokenAction} from "../../contracts/external/actions/nTokenAction.sol";
import {TreasuryAction} from "../../contracts/external/actions/TreasuryAction.sol";
import {IERC20} from "../../interfaces/IERC20.sol";
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

    AccountsData[5] private accounts;
    uint32 private emissionRatePerYear;
    uint256 private incentiveTokenDecimals;
    uint32 private endTime;

    function _getCurrencyRewardTokenAndForkBlock()
        internal
        virtual
        returns (uint16 currencyId, address rewardToken, uint256 marketInitializationBlock)
    {
        currencyId = 9;
        rewardToken = 0x912CE59144191C1204E64559FE8253a0e49E6548;
        marketInitializationBlock = 145559028;
    }

    function _depositWithInitialAccounts() private {
        uint256 totalInitialDeposit = 6e20;
        // all shares should add up to 95
        accounts[0] = AccountsData(vm.addr(12320), 10);
        accounts[1] = AccountsData(vm.addr(12321), 40);
        accounts[2] = AccountsData(vm.addr(12322), 15);
        accounts[3] = AccountsData(vm.addr(12323), 25);
        accounts[4] = AccountsData(vm.addr(12324), 5);

        for (uint256 i = 0; i < accounts.length; i++) {
            address account = accounts[i].account;
            uint256 amount = totalInitialDeposit * accounts[i].initialShare / 100;
            _depositAndMintNToken(CURRENCY_ID, account, amount);
        }
        // round all other deposits(including the one on initialization) to 5%
        // so it's easier to calculate rewards
        _depositAndMintNToken(CURRENCY_ID, vm.addr(12325), totalInitialDeposit * 5 / 100 - 0.05e18);
    }

    function setUp() public {
        (uint16 currencyId, address rewardToken, uint256 marketInitializationBlock) =
            _getCurrencyRewardTokenAndForkBlock();
        CURRENCY_ID = currencyId;
        REWARD_TOKEN = rewardToken;

        vm.createSelectFork(ARBITRUM_RPC_URL, marketInitializationBlock);
        _initializeMarket(currencyId);
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
        for (uint256 i = 0; i < accounts.length; i++) {
            uint256 reward = rewarder.getAccountRewardClaim(accounts[i].account, uint32(block.timestamp));
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

        for (uint256 i = 0; i < accounts.length; i++) {
            // forgefmt: disable-next-item
            uint256 predictedReward = totalGeneratedIncentive
                .mul(accounts[i].initialShare)
                .div(100)
                .div(Constants.INCENTIVE_ACCUMULATION_PRECISION);
            uint256 reward = rewarder.getAccountRewardClaim(accounts[i].account, uint32(block.timestamp));

            assertApproxEqAbs(reward / incentiveTokenDecimals, predictedReward, 1, vm.toString(i));
        }
    }

    function test_claimReward_ShouldBeAbleToClaimIncentivesManual(uint32 timeToSkip) public {
        timeToSkip = uint32(bound(timeToSkip, 1000, uint256(type(uint32).max / 10)));

        skip(timeToSkip);

        for (uint256 i = 0; i < accounts.length; i++) {
            uint256 reward = rewarder.getAccountRewardClaim(accounts[i].account, uint32(block.timestamp));

            assertEq(IERC20(REWARD_TOKEN).balanceOf(accounts[i].account), 0);

            vm.prank(accounts[i].account);
            NOTIONAL.nTokenClaimIncentives();

            assertEq(IERC20(REWARD_TOKEN).balanceOf(accounts[i].account), reward);
        }
    }

    function test_claimReward_SequentialManualClaims() public {
        uint32 timeToSkip = 1 weeks;

        skip(timeToSkip);

        for (uint256 i = 0; i < accounts.length; i++) {
            uint256 reward = rewarder.getAccountRewardClaim(accounts[i].account, uint32(block.timestamp));
            assertTrue(reward != 0);

            assertEq(IERC20(REWARD_TOKEN).balanceOf(accounts[i].account), 0);

            vm.prank(accounts[i].account);
            NOTIONAL.nTokenClaimIncentives();

            assertEq(IERC20(REWARD_TOKEN).balanceOf(accounts[i].account), reward);
        }
        // second skip
        skip(2 weeks);

        for (uint256 i = 0; i < accounts.length; i++) {
            uint256 reward = rewarder.getAccountRewardClaim(accounts[i].account, uint32(block.timestamp));
            assertTrue(reward != 0);

            uint256 prevBal = IERC20(REWARD_TOKEN).balanceOf(accounts[i].account);

            vm.prank(accounts[i].account);
            NOTIONAL.nTokenClaimIncentives();

            uint256 newBal = IERC20(REWARD_TOKEN).balanceOf(accounts[i].account);

            assertEq(newBal, prevBal + reward);
        }
    }

    function test_claimReward_TransferOfNTokenShouldTriggerClaim(uint32 timeToSkip) public {
        timeToSkip = uint32(bound(timeToSkip, 1000, uint256(type(uint32).max / 10)));

        skip(timeToSkip);

        for (uint256 i = 0; i < accounts.length; i++) {
            uint256 reward = rewarder.getAccountRewardClaim(accounts[i].account, uint32(block.timestamp));

            assertEq(IERC20(REWARD_TOKEN).balanceOf(accounts[i].account), 0);

            // transfer should trigger claim
            vm.prank(accounts[i].account);
            IERC20(NTOKEN).transfer(vm.addr(111111), 100);

            assertEq(IERC20(REWARD_TOKEN).balanceOf(accounts[i].account), reward);
        }
    }

    function test_claimReward_ShouldClaimFullAmountAfterTheEnd() public {
        uint256 startTime = block.timestamp;
        uint32 incentivePeriod = endTime - uint32(block.timestamp);
        // forgefmt: disable-next-item
        uint256 totalIncentives = (endTime - block.timestamp)
                .mul(emissionRatePerYear)
                .div(Constants.YEAR);

        // skip 10% of incentive period, should be able to clam 10% of the total amount
        uint8 incentiveTimePassed = 10; // percentage
        uint8 claimed = 0;
        uint8 rewardLeft = incentiveTimePassed - claimed;
        vm.warp(startTime + incentivePeriod * incentiveTimePassed/100);
        for (uint256 i = 0; i < accounts.length; i++) {
            // forgefmt: disable-next-item
            uint256 reward = totalIncentives
                .mul(accounts[i].initialShare)
                .div(100)
                .mul(rewardLeft)
                .div(100);
            assertTrue(reward != 0, "11");

            uint256 prevBal = IERC20(REWARD_TOKEN).balanceOf(accounts[i].account);
            assertEq(prevBal, 0);

            vm.prank(accounts[i].account);
            NOTIONAL.nTokenClaimIncentives();

            uint256 newBal = IERC20(REWARD_TOKEN).balanceOf(accounts[i].account);
            assertApproxEqAbs(newBal.div(incentiveTokenDecimals), reward, 1, "12");
        }
        claimed = incentiveTimePassed;

        // skip 40% of incentive period
        incentiveTimePassed = 40;
        rewardLeft = incentiveTimePassed - claimed;
        // should claim full amount
        vm.warp(startTime + incentivePeriod * incentiveTimePassed / 100);
        for (uint256 i = 0; i < accounts.length; i++) {
            // forgefmt: disable-next-item
            uint256 reward = totalIncentives
                .mul(accounts[i].initialShare)
                .div(100)
                .mul(rewardLeft)
                .div(100);
            assertTrue(reward != 0, "21");

            uint256 prevBal = IERC20(REWARD_TOKEN).balanceOf(accounts[i].account);

            vm.prank(accounts[i].account);
            NOTIONAL.nTokenClaimIncentives();

            uint256 newBal = IERC20(REWARD_TOKEN).balanceOf(accounts[i].account);
            assertApproxEqAbs(newBal.sub(prevBal).div(incentiveTokenDecimals), reward, 1, "22");
        }
        claimed = incentiveTimePassed;

        // skip 70% of incentive period
        incentiveTimePassed = 70;
        rewardLeft = incentiveTimePassed - claimed;
        // should claim full amount
        vm.warp(startTime + incentivePeriod * incentiveTimePassed / 100);
        for (uint256 i = 0; i < accounts.length; i++) {
            // forgefmt: disable-next-item
            uint256 reward = totalIncentives
                .mul(accounts[i].initialShare)
                .div(100)
                .mul(rewardLeft)
                .div(100);
            assertTrue(reward != 0, "31");

            uint256 prevBal = IERC20(REWARD_TOKEN).balanceOf(accounts[i].account);

            vm.prank(accounts[i].account);
            NOTIONAL.nTokenClaimIncentives();

            uint256 newBal = IERC20(REWARD_TOKEN).balanceOf(accounts[i].account);
            assertApproxEqAbs(newBal.sub(prevBal).div(incentiveTokenDecimals), reward, 1, "32");
        }
        claimed = incentiveTimePassed;


        // skip 100% of incentive period
        incentiveTimePassed = 100;
        rewardLeft = incentiveTimePassed - claimed;
        // should claim full amount
        vm.warp(startTime + incentivePeriod * incentiveTimePassed / 100);

        for (uint256 i = 0; i < accounts.length; i++) {
            // forgefmt: disable-next-item
            uint256 reward = totalIncentives
                .mul(accounts[i].initialShare)
                .div(100)
                .mul(rewardLeft)
                .div(100);
            assertTrue(reward != 0, "l1");

            uint256 prevBal = IERC20(REWARD_TOKEN).balanceOf(accounts[i].account);

            vm.prank(accounts[i].account);
            NOTIONAL.nTokenClaimIncentives();

            uint256 newBal = IERC20(REWARD_TOKEN).balanceOf(accounts[i].account);
            assertApproxEqAbs(newBal.sub(prevBal).div(incentiveTokenDecimals), reward, 1, "l2");
        }
        // another skip after everything is claimed, should claim 0
        skip(1 weeks);

        for (uint256 i = 0; i < accounts.length; i++) {
            uint256 reward = rewarder.getAccountRewardClaim(accounts[i].account, uint32(block.timestamp));
            assertTrue(reward == 0, "a1");

            uint256 prevBal = IERC20(REWARD_TOKEN).balanceOf(accounts[i].account);

            vm.prank(accounts[i].account);
            NOTIONAL.nTokenClaimIncentives();

            uint256 newBal = IERC20(REWARD_TOKEN).balanceOf(accounts[i].account);

            assertEq(newBal, prevBal, "a2");
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
