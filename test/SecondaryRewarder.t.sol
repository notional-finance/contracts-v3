// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;
pragma abicoder v2;

import {Test} from "forge-std/Test.sol";

import {Router} from "../contracts/external/Router.sol";
import {TreasuryAction} from "../contracts/external/actions/TreasuryAction.sol";
import {NotionalProxy} from "../interfaces/notional/NotionalProxy.sol";
import {IERC20} from "../interfaces/IERC20.sol";
import {SecondaryRewarder} from "../contracts/internal/balances/SecondaryRewarder.sol";

contract SecondaryRewarderTest is Test {
    NotionalProxy constant public NOTIONAL = NotionalProxy(0x1344A36A1B56144C3Bc62E7757377D288fDE0369);
    string public ARBITRUM_RPC_URL = vm.envString("ARBITRUM_RPC_URL");
    uint256 public ARBITRUM_FORK_BLOCK = 152642413;

    SecondaryRewarder private rewarder;
    address private owner;

    function getDeployedContracts() internal view returns (Router.DeployedContracts memory c) {
        Router r = Router(payable(address(NOTIONAL)));
        c.governance = r.GOVERNANCE();
        c.views = r.VIEWS();
        c.initializeMarket = r.INITIALIZE_MARKET();
        c.nTokenActions = r.NTOKEN_ACTIONS();
        c.batchAction = r.BATCH_ACTION();
        c.accountAction = r.ACCOUNT_ACTION();
        c.erc1155 = r.ERC1155();
        c.liquidateCurrency = r.LIQUIDATE_CURRENCY();
        c.liquidatefCash = r.LIQUIDATE_FCASH();
        c.treasury = r.TREASURY();
        c.calculationViews = r.CALCULATION_VIEWS();
        c.vaultAccountAction = r.VAULT_ACCOUNT_ACTION();
        c.vaultLiquidationAction = r.VAULT_LIQUIDATION_ACTION();
        c.vaultAccountHealth = r.VAULT_ACCOUNT_HEALTH();
    }

    function upgradeTo(Router.DeployedContracts memory c) internal returns (Router r) {
        r = new Router(c);
        vm.prank(owner);
        NOTIONAL.upgradeTo(address(r));
    }

    function _getCurrencyAndRewardToken() internal virtual returns (uint16, address) {
        return (3, 0x1344A36A1B56144C3Bc62E7757377D288fDE0369);
    }

    function setUp() public {
        vm.createSelectFork(ARBITRUM_RPC_URL, ARBITRUM_FORK_BLOCK);
        (uint16 currencyId, address rewardToken) = _getCurrencyAndRewardToken();
        address nTokenAddress = NOTIONAL.nTokenAddress(currencyId);
        rewarder = new SecondaryRewarder(
            address(NOTIONAL),
            nTokenAddress,
            rewardToken,
            1e5,
            uint32(block.timestamp + 365 days)
        );
        owner = NOTIONAL.owner();

        Router.DeployedContracts memory c = getDeployedContracts();
        c.treasury = address(new TreasuryAction(TreasuryAction(c.treasury).COMPTROLLER()));
        upgradeTo(c);

        vm.prank(owner);
        NOTIONAL.setSecondaryIncentiveRewarder(currencyId, rewarder);
    }

    function test_setIncentiveEmissionRate_ShouldFailIfNotOwner() public {
        vm.expectRevert("Only owner");
        rewarder.setIncentiveEmissionRate(10e4, uint32(block.timestamp));

    }

    function test_setIncentiveEmissionRate_OwnerCanSetEmissionRate() public {
        uint32 emissionRate = rewarder.emissionRatePerYear();
        uint32 endTime = rewarder.endTime();

        assertTrue(0 < emissionRate, "1");
        assertTrue(0 < endTime, "2");

        uint32 newEmissionRate = 2 * emissionRate;
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

    function test_recover_OwnerCanRecoverAnyToken() public {
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

    function test_setSecondaryIncentiveRewarder_ShouldFailIfNotOwner() public {
        vm.expectRevert("Ownable: caller is not the owner");
        NOTIONAL.setSecondaryIncentiveRewarder(3, rewarder);
    }

}
