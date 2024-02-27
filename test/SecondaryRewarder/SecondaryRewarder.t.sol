// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;
pragma abicoder v2;

import {SecondaryRewarderSetupTest} from "./SecondaryRewarderSetupTest.sol";
import {Router} from "../../contracts/external/Router.sol";
import {TreasuryAction} from "../../contracts/external/actions/TreasuryAction.sol";
import {IERC20} from "../../interfaces/IERC20.sol";
import {SecondaryRewarder} from "../../contracts/external/adapters/SecondaryRewarder.sol";
import {Constants} from "../../contracts/global/Constants.sol";

contract SecondaryRewarderTest is SecondaryRewarderSetupTest {
    SecondaryRewarder private rewarder;
    address private owner;
    uint16 private CURRENCY_ID;
    address private rewardToken;

    function _getCurrencyAndRewardToken() internal virtual returns (uint16, address) {
        return (3, 0x912CE59144191C1204E64559FE8253a0e49E6548);
    }

    function setUp() public {
        defaultFork();

        (uint16 currencyId, address _rewardToken) = _getCurrencyAndRewardToken();
        CURRENCY_ID = currencyId;
        rewardToken = _rewardToken;
        rewarder = new SecondaryRewarder(
            NOTIONAL,
            currencyId,
            IERC20(_rewardToken),
            1e5,
            uint32(block.timestamp + Constants.YEAR)
        );
        owner = NOTIONAL.owner();

        Router.DeployedContracts memory c = getDeployedContracts();
        c.treasury = address(new TreasuryAction());
        upgradeTo(c);

        vm.prank(owner);
        NOTIONAL.setSecondaryIncentiveRewarder(currencyId, rewarder);
    }

    function test_setIncentiveEmissionRate_ShouldFailIfNotOwner() public {
        vm.expectRevert("Only owner");
        rewarder.setIncentiveEmissionRate(10e4, uint32(block.timestamp));
    }

    function test_setIncentiveEmissionRate_OwnerCanSetEmissionRate() public {
        uint128 emissionRate = rewarder.emissionRatePerYear();
        uint32 endTime = rewarder.endTime();

        assertTrue(0 < emissionRate, "1");
        assertTrue(0 < endTime, "2");

        uint128 newEmissionRate = 2 * emissionRate;
        uint32 newEndTime = 2 * endTime;
        vm.prank(owner);
        rewarder.setIncentiveEmissionRate(newEmissionRate, newEndTime);

        assertTrue(rewarder.emissionRatePerYear() == newEmissionRate, "3");
        assertTrue(rewarder.endTime() == newEndTime, "4");
    }

    function test_recover_ShouldFailIfNotOwner() public {
        address someToken = 0xDA10009cBd5D07dd0CeCc66161FC93D7c9000da1;
        uint256 amount = 1000e18;
        deal(someToken, address(rewarder), amount);

        vm.expectRevert("Only owner");
        rewarder.recover(someToken, amount);
    }

    function test_recover_OwnerCanRecoverAnyERC20() public {
        IERC20 someToken = IERC20(0xDA10009cBd5D07dd0CeCc66161FC93D7c9000da1);
        uint256 amount = 1000e18;
        deal(address(someToken), address(rewarder), amount);

        uint256 ownerPreBalance = someToken.balanceOf(owner);
        uint256 rewarderPreBalance = someToken.balanceOf(address(rewarder));

        vm.prank(owner);
        rewarder.recover(address(someToken), amount);

        uint256 ownerPostBalance = someToken.balanceOf(owner);
        uint256 rewarderPostBalance = someToken.balanceOf(address(rewarder));

        assertLt(ownerPreBalance, ownerPostBalance);
        assertEq(ownerPreBalance + amount, ownerPostBalance);
        assertLt(rewarderPostBalance, rewarderPreBalance);
        assertEq(rewarderPreBalance - amount, rewarderPostBalance);
    }

    function test_recover_OwnerCanRecoverEth() public {
        uint256 amount = 1000e18;
        deal(address(rewarder), amount);

        uint256 ownerPreBalance = owner.balance;
        uint256 rewarderPreBalance = address(rewarder).balance;

        vm.prank(owner);
        rewarder.recover(Constants.ETH_ADDRESS, amount);

        uint256 ownerPostBalance = owner.balance;
        uint256 rewarderPostBalance = address(rewarder).balance;

        assertLt(ownerPreBalance, ownerPostBalance);
        assertEq(ownerPreBalance + amount, ownerPostBalance);
        assertLt(rewarderPostBalance, rewarderPreBalance);
        assertEq(rewarderPreBalance - amount, rewarderPostBalance);
    }

    function test_setSecondaryIncentiveRewarder_ShouldFailIfNotOwner() public {
        vm.expectRevert("Ownable: caller is not the owner");
        NOTIONAL.setSecondaryIncentiveRewarder(CURRENCY_ID, rewarder);
    }

    function test_setSecondaryIncentiveRewarder_OwnerShouldBeAbleToSetNewRewarder() public {
        SecondaryRewarder newRewarder = new SecondaryRewarder(
            NOTIONAL,
            CURRENCY_ID,
            IERC20(rewardToken),
            1e5,
            uint32(block.timestamp + Constants.YEAR)
        );
        vm.prank(owner);
        NOTIONAL.setSecondaryIncentiveRewarder(CURRENCY_ID, newRewarder);

        // previous rewarder should be detached
        assertEq(uint256(rewarder.emissionRatePerYear()), 0);
        assertEq(uint256(rewarder.endTime()), block.timestamp);
    }

    function test_claimRewardsDirect_ShouldClaimZeroIfThereIsNoReward() public {
        address accountWithNoNTokens = vm.addr(4234234);
        vm.startPrank(accountWithNoNTokens);
        assertEq(rewarder.getAccountRewardClaim(accountWithNoNTokens, uint32(block.timestamp)), 0);
        vm.stopPrank();
    }

    function test_detach_ShouldFailIfNotNotional() public {
        vm.expectRevert("Only Notional");
        rewarder.detach();
    }

    function test_detach_ShouldSetEmissionToZeroAndEndTime() public {
        vm.prank(address(NOTIONAL));
        rewarder.detach();
    }

    function test_setSecondaryIncentiveRewarder_OwnerShouldBeAbleToTurnOffRewarder() public {
        vm.prank(owner);
        NOTIONAL.setSecondaryIncentiveRewarder(CURRENCY_ID, SecondaryRewarder(address(0)));

        // previous rewarder should be detached
        assertEq(uint256(rewarder.emissionRatePerYear()), 0);
        assertEq(uint256(rewarder.endTime()), block.timestamp);
    }
}