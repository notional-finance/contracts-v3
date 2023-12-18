// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;
pragma abicoder v2;

import {SecondaryRewarderSetupTest} from "./SecondaryRewarderSetupTest.sol";
import {Router} from "../../contracts/external/Router.sol";
import {BatchAction} from "../../contracts/external/actions/BatchAction.sol";
import {nTokenAction} from "../../contracts/external/actions/nTokenAction.sol";
import {TreasuryAction} from "../../contracts/external/actions/TreasuryAction.sol";
import {AccountAction} from "../../contracts/external/actions/AccountAction.sol";
import {IERC20} from "../../interfaces/IERC20.sol";
import {SecondaryRewarder} from "../../contracts/external/adapters/SecondaryRewarder.sol";
import {Constants} from "../../contracts/global/Constants.sol";
import {SafeInt256} from "../../contracts/math/SafeInt256.sol";
import {SafeUint256} from "../../contracts/math/SafeUint256.sol";

abstract contract ClaimRewards is SecondaryRewarderSetupTest {
    using SafeUint256 for uint256;
    using SafeInt256 for int256;

    SecondaryRewarder private rewarder;
    address private owner;
    uint16 private CURRENCY_ID;
    address private REWARD_TOKEN;
    address private NTOKEN;

    struct AccountsData {
        address account;
        uint16 initialShare;
    }

    AccountsData[5] private accounts;
    uint128 private emissionRatePerYear;
    uint256 private incentiveTokenDecimals;
    uint32 private endTime;

    function _getRewardToken() internal virtual returns(address); 

    function _getCurrencyRewardTokenAndForkBlock()
        internal
        returns (uint16 currencyId, address rewardToken)
    {
        currencyId = 9;
        rewardToken = _getRewardToken();
    }

    function _fork() internal {
        vm.createSelectFork(ARBITRUM_RPC_URL, 145559028); // CbEth deployment time
        _initializeMarket(CURRENCY_ID);
    }

    function _depositWithInitialAccounts() private {
        uint256 totalInitialDeposit = 6e20;
        // all shares should add up to 95
        accounts[0] = AccountsData(0xD2162F65D5be7533220a4F016CCeCF0f9C1CADB3, 10);
        accounts[1] = AccountsData(0xf3A007b9d892Ace8cc3cb77444C3B9e556E263b2, 40);
        accounts[2] = AccountsData(0x4357b2A65E8AD9588B8614E8Fe589e518bDa5F2E, 15);
        accounts[3] = AccountsData(0xea0B1eeA6d1dFD490b9267c479E3f22049AAFa3B, 25);
        accounts[4] = AccountsData(0xA9908242897d282760341e415fcF120Ec15ecaC0, 5);

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
        (uint16 currencyId, address rewardToken) = _getCurrencyRewardTokenAndForkBlock();
        CURRENCY_ID = currencyId;
        REWARD_TOKEN = rewardToken;

        _fork();
        _depositWithInitialAccounts();

        NTOKEN = NOTIONAL.nTokenAddress(currencyId);
        emissionRatePerYear = 2e13;
        incentiveTokenDecimals = 10 ** IERC20(rewardToken).decimals();
        endTime = uint32(block.timestamp + Constants.YEAR);
        rewarder = new SecondaryRewarder(
            NOTIONAL,
            currencyId,
            IERC20(rewardToken),
            emissionRatePerYear,
            endTime
        );
        uint256 totalIncentives =
            emissionRatePerYear * incentiveTokenDecimals / uint256(Constants.INTERNAL_TOKEN_PRECISION);
        deal(REWARD_TOKEN, address(rewarder), totalIncentives);
        owner = NOTIONAL.owner();

        Router.DeployedContracts memory c = getDeployedContracts();
        c.batchAction = address(new BatchAction());
        c.accountAction = address(new AccountAction());
        c.treasury = address(new TreasuryAction());
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

    function testFuzz_getAccountRewardClaim_ShouldNotBeZeroAfterSomeTime(uint32 timeToSkip) public {
        timeToSkip = uint32(bound(timeToSkip, 0, uint256(type(uint32).max / 10)));
        uint40 starTime = uint40(block.timestamp);

        skip(timeToSkip);

        uint256 totalGeneratedIncentive = uint256(SafeInt256.min(timeToSkip, endTime - starTime))
            .mul(emissionRatePerYear)
            .mul(Constants.INCENTIVE_ACCUMULATION_PRECISION)
            .div(Constants.YEAR);

        for (uint256 i = 0; i < accounts.length; i++) {
            uint256 predictedReward = totalGeneratedIncentive
                .mul(accounts[i].initialShare)
                .div(100)
                .div(uint256(Constants.INTERNAL_TOKEN_PRECISION))
                .div(Constants.INCENTIVE_ACCUMULATION_PRECISION);
            uint256 reward = rewarder.getAccountRewardClaim(accounts[i].account, uint32(block.timestamp));

            assertApproxEqAbs(reward / incentiveTokenDecimals, predictedReward, 1, vm.toString(i));
        }
    }

    function testFuzz_claimReward_ShouldBeAbleToClaimIncentivesManual(uint32 timeToSkip) public {
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

    function testFuzz_claimReward_TransferOfNTokenShouldTriggerClaim(uint32 timeToSkip) public {
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
        uint256 totalIncentives = (endTime - block.timestamp)
                .mul(emissionRatePerYear)
                .div(Constants.YEAR);

        // skip 10% of incentive period, should be able to clam 10% of the total amount
        uint8 incentiveTimePassed = 10; // percentage
        uint8 claimed = 0;
        uint8 rewardLeft = incentiveTimePassed - claimed;
        vm.warp(startTime + incentivePeriod * incentiveTimePassed/100);
        for (uint256 i = 0; i < accounts.length; i++) {
            uint256 reward = totalIncentives
                .mul(accounts[i].initialShare)
                .div(100)
                .mul(rewardLeft)
                .div(100)
                .div(uint256(Constants.INTERNAL_TOKEN_PRECISION));
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
            uint256 reward = totalIncentives
                .mul(accounts[i].initialShare)
                .div(100)
                .mul(rewardLeft)
                .div(100)
                .div(uint256(Constants.INTERNAL_TOKEN_PRECISION));
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
            uint256 reward = totalIncentives
                .mul(accounts[i].initialShare)
                .div(100)
                .mul(rewardLeft)
                .div(100)
                .div(uint256(Constants.INTERNAL_TOKEN_PRECISION));
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
            uint256 reward = totalIncentives
                .mul(accounts[i].initialShare)
                .div(100)
                .mul(rewardLeft)
                .div(100)
                .div(uint256(Constants.INTERNAL_TOKEN_PRECISION));
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

    function test_claimReward_ShouldClaimCorrectAmountAfterEndTimeAndEmissionRateChange() public {
        uint256 startTime = block.timestamp;
        uint32 incentivePeriod = endTime - uint32(block.timestamp);
        uint256 totalIncentives = (endTime - block.timestamp).mul(emissionRatePerYear).div(Constants.YEAR);

        // skip 10% of incentive period, should be able to clam 10% of the total amount
        uint8 incentiveTimePassed = 10; // percentage
        uint8 claimed = 0;
        uint8 rewardLeft = incentiveTimePassed - claimed;
        vm.warp(startTime + (incentivePeriod * incentiveTimePassed) / 100);
        for (uint256 i = 0; i < accounts.length; i++) {
            uint256 reward = totalIncentives
                .mul(accounts[i].initialShare)
                .mul(rewardLeft)
                .div(100 * 100 * uint256(Constants.INTERNAL_TOKEN_PRECISION));
            assertTrue(reward != 0, "1");

            uint256 prevBal = IERC20(REWARD_TOKEN).balanceOf(accounts[i].account);
            assertEq(prevBal, 0);

            vm.prank(accounts[i].account);
            NOTIONAL.nTokenClaimIncentives();

            uint256 newBal = IERC20(REWARD_TOKEN).balanceOf(accounts[i].account);
            assertApproxEqAbs(newBal.div(incentiveTokenDecimals), reward, 1, "2");
        }
        claimed = incentiveTimePassed;

        // skip 100% of incentive period
        incentiveTimePassed = 100;
        rewardLeft = incentiveTimePassed - claimed;
        // should claim full amount
        vm.warp(startTime + (incentivePeriod * incentiveTimePassed) / 100);

        for (uint256 i = 0; i < accounts.length; i++) {
            uint256 reward = totalIncentives
                .mul(accounts[i].initialShare)
                .mul(rewardLeft)
                .div(100 * 100 * uint256(Constants.INTERNAL_TOKEN_PRECISION));
            assertTrue(reward != 0, "3");

            uint256 prevBal = IERC20(REWARD_TOKEN).balanceOf(accounts[i].account);

            vm.prank(accounts[i].account);
            NOTIONAL.nTokenClaimIncentives();

            uint256 newBal = IERC20(REWARD_TOKEN).balanceOf(accounts[i].account);
            assertApproxEqAbs(newBal.sub(prevBal).div(incentiveTokenDecimals), reward, 1, "4");
        }
        // another skip after everything is claimed, should claim 0
        skip(1 weeks);

        for (uint256 i = 0; i < accounts.length; i++) {
            uint256 reward = rewarder.getAccountRewardClaim(accounts[i].account, uint32(block.timestamp));
            assertTrue(reward == 0, "5");

            uint256 prevBal = IERC20(REWARD_TOKEN).balanceOf(accounts[i].account);

            vm.prank(accounts[i].account);
            NOTIONAL.nTokenClaimIncentives();

            uint256 newBal = IERC20(REWARD_TOKEN).balanceOf(accounts[i].account);

            assertEq(newBal, prevBal, "6");
        }

        // Change the incentive emission rate after the current endTime
        emissionRatePerYear = 1e13;
        incentivePeriod = 2 weeks;
        startTime = uint32(block.timestamp);
        endTime = uint32(block.timestamp + incentivePeriod);
        totalIncentives = uint256(incentivePeriod).mul(emissionRatePerYear).div(Constants.YEAR);
        deal(REWARD_TOKEN, address(rewarder), totalIncentives * incentiveTokenDecimals);

        vm.prank(owner);
        rewarder.setIncentiveEmissionRate(emissionRatePerYear, endTime);

        // Have the nTokens earn zero incentives between the old endTime and the time we change the emission rate
        // should claim zero right after start of new incentives
        for (uint256 i = 0; i < accounts.length; i++) {
            uint256 reward = rewarder.getAccountRewardClaim(accounts[i].account, uint32(block.timestamp));
            assertTrue(reward == 0);

            uint256 prevBal = IERC20(REWARD_TOKEN).balanceOf(accounts[i].account);

            vm.prank(accounts[i].account);
            NOTIONAL.nTokenClaimIncentives();

            uint256 newBal = IERC20(REWARD_TOKEN).balanceOf(accounts[i].account);

            assertEq(newBal, prevBal);
        }

        // Have the nTokens start earning incentives at the new emission rate from the time we change the emission rate
        // skip 30% of incentive period, should be able to clam 30% of the total amount
        incentiveTimePassed = 30; // percentage
        claimed = 0;
        rewardLeft = incentiveTimePassed - claimed;
        vm.warp(startTime + (incentivePeriod * incentiveTimePassed) / 100);
        for (uint256 i = 0; i < accounts.length; i++) {
            uint256 reward = totalIncentives
                .mul(accounts[i].initialShare)
                .mul(rewardLeft)
                .div(100 * 100 * uint256(Constants.INTERNAL_TOKEN_PRECISION));
            assertTrue(reward != 0, "7");

            uint256 prevBal = IERC20(REWARD_TOKEN).balanceOf(accounts[i].account);

            vm.prank(accounts[i].account);
            NOTIONAL.nTokenClaimIncentives();

            uint256 newBal = IERC20(REWARD_TOKEN).balanceOf(accounts[i].account);
            assertApproxEqAbs(newBal.sub(prevBal).div(incentiveTokenDecimals), reward, 1, "8");
        }
        claimed = incentiveTimePassed;

        // skip 100% of incentive period
        incentiveTimePassed = 100;
        rewardLeft = incentiveTimePassed - claimed;
        // should claim full amount
        vm.warp(startTime + (incentivePeriod * incentiveTimePassed) / 100);

        for (uint256 i = 0; i < accounts.length; i++) {
            uint256 reward = totalIncentives
                .mul(accounts[i].initialShare)
                .mul(rewardLeft)
                .div(100 * 100 * uint256(Constants.INTERNAL_TOKEN_PRECISION));
            assertTrue(reward != 0, "9");

            uint256 prevBal = IERC20(REWARD_TOKEN).balanceOf(accounts[i].account);

            vm.prank(accounts[i].account);
            NOTIONAL.nTokenClaimIncentives();

            uint256 newBal = IERC20(REWARD_TOKEN).balanceOf(accounts[i].account);
            assertApproxEqAbs(newBal.sub(prevBal).div(incentiveTokenDecimals), reward, 1, "10");
        }

        // another skip after everything is claimed, should claim 0
        skip(1 days);

        for (uint256 i = 0; i < accounts.length; i++) {
            uint256 reward = rewarder.getAccountRewardClaim(accounts[i].account, uint32(block.timestamp));
            assertTrue(reward == 0, "11");

            uint256 prevBal = IERC20(REWARD_TOKEN).balanceOf(accounts[i].account);

            vm.prank(accounts[i].account);
            NOTIONAL.nTokenClaimIncentives();

            uint256 newBal = IERC20(REWARD_TOKEN).balanceOf(accounts[i].account);

            assertEq(newBal, prevBal, "12");
        }
    }

    function testFuzz_claimReward_RedeemOfNTokenShouldTriggerClaim(uint32 timeToSkip) public {
        // set upper bond to 6 weeks to avoid need for settlement
        timeToSkip = uint32(bound(timeToSkip, 0, uint256(6 weeks)));

        skip(timeToSkip);

        for (uint256 i = 0; i < accounts.length; i++) {
            address account = accounts[i].account;
            uint256 reward = rewarder.getAccountRewardClaim(account, uint32(block.timestamp));
            assertTrue(reward != 0 || timeToSkip < 1 hours);

            assertEq(IERC20(REWARD_TOKEN).balanceOf(account), 0);

            uint256 prevNTokenBal = IERC20(NTOKEN).balanceOf(account);
            // trigger claim
            vm.prank(account);
            _depositAndMintNToken(CURRENCY_ID, account, 1e18);

            uint256 newNTokenBal = IERC20(NTOKEN).balanceOf(account);

            assertEq(prevNTokenBal + 1e8, newNTokenBal);

            assertEq(IERC20(REWARD_TOKEN).balanceOf(account), reward);

        }
    }

    function testFuzz_claimReward_MintOfNTokenShouldTriggerClaim(uint32 timeToSkip) public {
        // set upper bond to 6 weeks to avoid need for settlement
        timeToSkip = uint32(bound(timeToSkip, 0, uint256(6 weeks)));

        skip(timeToSkip);

        for (uint256 i = 0; i < accounts.length; i++) {
            address account = accounts[i].account;
            uint256 reward = rewarder.getAccountRewardClaim(account, uint32(block.timestamp));
            assertTrue(reward != 0 || timeToSkip < 1 hours, "1");

            assertEq(IERC20(REWARD_TOKEN).balanceOf(account), 0, "2");

            uint256 prevNTokenBal = IERC20(NTOKEN).balanceOf(account);
            // trigger claim
            vm.prank(account);
            NOTIONAL.nTokenRedeem(account, CURRENCY_ID, 100, true, true);

            uint256 newNTokenBal = IERC20(NTOKEN).balanceOf(account);

            assertEq(prevNTokenBal, newNTokenBal + 100, "3");

            assertEq(IERC20(REWARD_TOKEN).balanceOf(account), reward, "4");

        }
    }
}

contract ClaimRewardsARB is ClaimRewards {
    function _getRewardToken() internal pure override returns(address) {
        return 0x912CE59144191C1204E64559FE8253a0e49E6548;
    }
}

contract ClaimRewardsUSDC is ClaimRewards {
    function _getRewardToken() internal pure override returns(address) {
        return 0xaf88d065e77c8cC2239327C5EDb3A432268e5831;
    }
}

contract ClaimRewardsLido is ClaimRewards {
    function _getRewardToken() internal pure override returns(address) {
        return 0x13Ad51ed4F1B7e9Dc168d8a00cB3f4dDD85EfA60;
    }
}