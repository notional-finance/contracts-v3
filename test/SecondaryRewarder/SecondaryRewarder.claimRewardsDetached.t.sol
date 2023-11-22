// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;
pragma abicoder v2;

import {SecondaryRewarderSetupTest} from "./SecondaryRewarderSetupTest.sol";
import {Router} from "../../contracts/external/Router.sol";
import {BatchAction} from "../../contracts/external/actions/BatchAction.sol";
import {nTokenAction} from "../../contracts/external/actions/nTokenAction.sol";
import {TreasuryAction} from "../../contracts/external/actions/TreasuryAction.sol";
import {IERC20} from "../../interfaces/IERC20.sol";
import {SecondaryRewarder} from "../../contracts/external/adapters/SecondaryRewarder.sol";
import {Constants} from "../../contracts/global/Constants.sol";
import {SafeInt256} from "../../contracts/math/SafeInt256.sol";
import {SafeUint256} from "../../contracts/math/SafeUint256.sol";

abstract contract ClaimRewardsDetached is SecondaryRewarderSetupTest {
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
    bytes32 private merkleRoot = 0x71011f1abc031fd85071453fd542c8c4164104c646c274887866794f00ca461b;
    bytes32[][5] private accountsProofs;

    uint32 private emissionRatePerYear;
    uint256 private incentiveTokenDecimals;
    uint256 private incentivePeriod;
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
    /// @dev Following merkle proofs were pregenerated with script/GenerateMerkleTree and data:
    /// "accounts": [
    ///     "0xD2162F65D5be7533220a4F016CCeCF0f9C1CADB3",
    ///     "0xf3A007b9d892Ace8cc3cb77444C3B9e556E263b2",
    ///     "0x4357b2A65E8AD9588B8614E8Fe589e518bDa5F2E",
    ///     "0xea0B1eeA6d1dFD490b9267c479E3f22049AAFa3B",
    ///     "0xA9908242897d282760341e415fcF120Ec15ecaC0"
    /// ],
    //  (totalInitialDeposit * initialShare)
    /// "nTokenBalances": [
    ///     "6000000000",
    ///     "24000000000",
    ///     "9000000000",
    ///     "15000000000",
    ///     "3000000000"
    /// ]
    function _setProofs() internal {
        accountsProofs[0] = [
            bytes32(0x6bd2121dd924640b7ddea39b23440e5eef854eb0a9d4d94b67827f2aec60c504),
            bytes32(0x010c06f06417d84ec70bab3c7d6f2208fc5a29fb06a8f0dcb031565fffae7c65),
            bytes32(0xef38359cc22b751c2c4588c27836688029c596a2177b80d5eec966048d61dc9e)
        ];
        accountsProofs[1] = [
            bytes32(0x768e538337c9326c2c639c5a303857d089772dd415c0877a7c462af2bc583785),
            bytes32(0x010c06f06417d84ec70bab3c7d6f2208fc5a29fb06a8f0dcb031565fffae7c65),
            bytes32(0xef38359cc22b751c2c4588c27836688029c596a2177b80d5eec966048d61dc9e)
        ];
        accountsProofs[2] = [
            bytes32(0x089660216bfffc7558ce6bfcd0a0aac24c638cbb883e8ac177692eafde5c1545),
            bytes32(0x3309795851f55b23eba7eec7a5408ddc155d703c4170fc0d4466a31a5277e2ad),
            bytes32(0xef38359cc22b751c2c4588c27836688029c596a2177b80d5eec966048d61dc9e)
        ];
        accountsProofs[3] = [
            bytes32(0x72c7c08203b4967a54c89188630c17fc5f5092442b856ef53d49467feb97e048),
            bytes32(0x3309795851f55b23eba7eec7a5408ddc155d703c4170fc0d4466a31a5277e2ad),
            bytes32(0xef38359cc22b751c2c4588c27836688029c596a2177b80d5eec966048d61dc9e)
        ];
        accountsProofs[4] = [
            bytes32(0x0000000000000000000000000000000000000000000000000000000000000000),
            bytes32(0x0000000000000000000000000000000000000000000000000000000000000000),
            bytes32(0xf0bffae834d422564b792a3443df7b7589e8c67db0c97d2215bd2a2e058a0fc7)
        ];
    }

    function setUp() public {
        (uint16 currencyId, address rewardToken) = _getCurrencyRewardTokenAndForkBlock();
        CURRENCY_ID = currencyId;
        REWARD_TOKEN = rewardToken;

        _fork();

        _depositWithInitialAccounts();
        _setProofs();

        NTOKEN = NOTIONAL.nTokenAddress(currencyId);
        emissionRatePerYear = 2e5;
        incentiveTokenDecimals = 10 ** IERC20(rewardToken).decimals();
        incentivePeriod = Constants.YEAR;
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
        c.treasury = address(new TreasuryAction());
        c.nTokenActions = address(new nTokenAction());
        upgradeTo(c);

        vm.prank(owner);
        NOTIONAL.setSecondaryIncentiveRewarder(currencyId, rewarder);
    }

    function _deployNewRewarder() internal returns (SecondaryRewarder newRewarder) {
        newRewarder = new SecondaryRewarder(
            NOTIONAL,
            CURRENCY_ID,
            IERC20(REWARD_TOKEN),
            emissionRatePerYear,
            uint32(endTime + Constants.YEAR)
        );
    }

    function test_detach_AfterIncentivePeriodEndsDetachShouldNotChangeEndTime() public {
        vm.warp(endTime + 1);
        vm.startPrank(owner);
        NOTIONAL.setSecondaryIncentiveRewarder(CURRENCY_ID, _deployNewRewarder());

        assertEq(uint256(rewarder.endTime()), uint256(endTime), "1");
        assertEq(rewarder.detached(), true, "2");
        assertEq(uint256(rewarder.emissionRatePerYear()), 0, "3");
    }

    function test_detach_BeforeIncentivePeriodEndsDetachShouldSetEndTimeToBlockTime() public {
        skip(1 weeks);

        vm.startPrank(owner);
        NOTIONAL.setSecondaryIncentiveRewarder(CURRENCY_ID, _deployNewRewarder());

        assertEq(uint256(rewarder.endTime()), block.timestamp, "1");
        assertEq(rewarder.detached(), true, "2");
        assertEq(uint256(rewarder.emissionRatePerYear()), 0, "3");
    }

    function test_getAccountRewardClaim_ShouldBeAbleToCheckWithMerkleProofAfterDetach() public {
        vm.warp(endTime + 1);

        // detach current rewarder
        vm.startPrank(owner);
        NOTIONAL.setSecondaryIncentiveRewarder(CURRENCY_ID, _deployNewRewarder());
        vm.stopPrank();

        vm.prank(owner);
        rewarder.setMerkleRoot(merkleRoot);

        uint256 totalGeneratedIncentive = incentivePeriod
            .mul(emissionRatePerYear)
            .mul(Constants.INCENTIVE_ACCUMULATION_PRECISION)
            .div(Constants.YEAR);

        for (uint256 i = 0; i < accounts.length; i++) {
            uint256 predictedReward = totalGeneratedIncentive
                .mul(accounts[i].initialShare)
                .div(100)
                .div(uint256(Constants.INTERNAL_TOKEN_PRECISION))
                .div(Constants.INCENTIVE_ACCUMULATION_PRECISION);
            uint256 ntTokenBalance = IERC20(NTOKEN).balanceOf(accounts[i].account);
            uint256 reward = rewarder.getAccountRewardClaim(accounts[i].account, ntTokenBalance, accountsProofs[i]);

            assertApproxEqAbs(reward / incentiveTokenDecimals, predictedReward, 1, vm.toString(i));
        }
    }

    function test_claimRewardsDirect_ShouldBeAbleToClaimAfterDetachAndAfterMerkleRootIsSet() public {
        vm.warp(endTime + 1);

        // detach current rewarder
        vm.startPrank(owner);
        NOTIONAL.setSecondaryIncentiveRewarder(CURRENCY_ID, _deployNewRewarder());
        vm.stopPrank();

        vm.prank(owner);
        rewarder.setMerkleRoot(merkleRoot);

        for (uint256 i = 0; i < accounts.length; i++) {
            address account = accounts[i].account;
            uint256 nTokenBalance = IERC20(NTOKEN).balanceOf(account);
            uint256 reward = rewarder.getAccountRewardClaim(account, nTokenBalance, accountsProofs[i]);

            assertEq(IERC20(REWARD_TOKEN).balanceOf(account), 0);

            vm.prank(accounts[i].account);
            rewarder.claimRewardsDirect(account, nTokenBalance, accountsProofs[i]);

            assertEq(IERC20(REWARD_TOKEN).balanceOf(accounts[i].account), reward);

            // claiming second time in same block should not change anything
            vm.prank(accounts[i].account);
            rewarder.claimRewardsDirect(account, nTokenBalance, accountsProofs[i]);

            assertEq(IERC20(REWARD_TOKEN).balanceOf(accounts[i].account), reward);
        }

        skip(1 weeks);
        // claiming second time after some time should not change anything
        for (uint256 i = 0; i < accounts.length; i++) {
            address account = accounts[i].account;
            uint256 nTokenBalance = IERC20(NTOKEN).balanceOf(account);
            uint256 reward = rewarder.getAccountRewardClaim(account, nTokenBalance, accountsProofs[i]);
            assertEq(reward, 0);

            uint256 prevBalance = IERC20(REWARD_TOKEN).balanceOf(account);

            vm.prank(accounts[i].account);
            rewarder.claimRewardsDirect(account, nTokenBalance, accountsProofs[i]);

            assertEq(IERC20(REWARD_TOKEN).balanceOf(accounts[i].account), prevBalance);
        }
    }
    function test_claimRewardsDirect_ShouldFailWithInvalidMerkleRoot() public {
        vm.warp(endTime + 1);

        // detach current rewarder
        vm.startPrank(owner);
        NOTIONAL.setSecondaryIncentiveRewarder(CURRENCY_ID, SecondaryRewarder(address(0)));
        vm.stopPrank();

        vm.prank(owner);
        // invalid merkle root
        rewarder.setMerkleRoot(0x71011f1abc031fd85071453fd542c8c4164104c646c274887866794f00000000);

        for (uint256 i = 0; i < accounts.length; i++) {
            address account = accounts[i].account;
            uint256 nTokenBalance = IERC20(NTOKEN).balanceOf(account);

            vm.expectRevert("NotInMerkle");
            rewarder.getAccountRewardClaim(account, nTokenBalance, accountsProofs[i]);

            vm.prank(accounts[i].account);
            vm.expectRevert("NotInMerkle");
            rewarder.claimRewardsDirect(account, nTokenBalance, accountsProofs[i]);
        }
    }
}

contract ClaimRewardsDetachedARB is ClaimRewardsDetached {
    function _getRewardToken() internal pure override returns(address) {
        return 0x912CE59144191C1204E64559FE8253a0e49E6548;
    }
}

contract ClaimRewardsDetachedUSDC is ClaimRewardsDetached {
    function _getRewardToken() internal pure override returns(address) {
        return 0xaf88d065e77c8cC2239327C5EDb3A432268e5831;
    }
}

contract ClaimRewardsDetachedLido is ClaimRewardsDetached {
    function _getRewardToken() internal pure override returns(address) {
        return 0x13Ad51ed4F1B7e9Dc168d8a00cB3f4dDD85EfA60;
    }
}