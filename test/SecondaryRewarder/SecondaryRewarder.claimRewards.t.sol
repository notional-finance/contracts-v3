// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;
pragma abicoder v2;

import {SecondaryRewarderSetupTest} from "./SecondaryRewarderSetupTest.sol";
import {Router} from "../../contracts/external/Router.sol";
import {TreasuryAction} from "../../contracts/external/actions/TreasuryAction.sol";
import {IERC20} from "../../interfaces/IERC20.sol";
import {BalanceAction, DepositActionType} from "../../contracts/global/Types.sol";
import {SecondaryRewarder} from "../../contracts/internal/balances/SecondaryRewarder.sol";
import {Constants} from "../../contracts/global/Constants.sol";

contract ClaimRewards is SecondaryRewarderSetupTest {
    SecondaryRewarder private rewarder;
    IERC20 private cbEth = IERC20(0x1DEBd73E752bEaF79865Fd6446b0c970EaE7732f);
    address private owner;
    uint16 private CURRENCY_ID;

    struct AccountsData {
        address account;
        uint16 initialShare;
    }

    function _getCurrencyAndRewardToken() internal virtual returns (uint16, address) {
        return (3, 0x912CE59144191C1204E64559FE8253a0e49E6548);
    }

    function initializeCbEthMarket() internal {
        address fundingAccount = 0x7d7935EDd4b6cDB5f34B0E1cCEAF85a3C4A11254;
        BalanceAction[] memory balanceActions = new BalanceAction[](1);
        BalanceAction memory balanceAction =
            BalanceAction(DepositActionType.DepositUnderlyingAndMintNToken, 9, 0.05e18, 0, false, true);
        balanceActions[0] = balanceAction;

        vm.startPrank(fundingAccount);
        cbEth.approve(address(NOTIONAL), 0.05e18);
        NOTIONAL.batchBalanceAction(fundingAccount, balanceActions);
        NOTIONAL.initializeMarkets(9, true);
        vm.stopPrank();
    }

    function depositWithInitialAccounts() private {
        uint256 totalInitialDeposit = 1e23;
        AccountsData[3] memory initialAccounts = [
            AccountsData(vm.addr(12321), 10),
            AccountsData(vm.addr(12322), 40),
            AccountsData(vm.addr(12323), 50)
        ];
        for (uint256 i = 0; i < initialAccounts.length; i++) {
            address account = initialAccounts[i].account;
            uint256 amount = totalInitialDeposit * initialAccounts[i].initialShare / 100;
            vm.startPrank(account);
            cbEth.approve(address(NOTIONAL), amount);
            vm.stopPrank();
        }
    }

    function setUp() public {
        forkAfterCbEthDeploy();
        initializeCbEthMarket();
        depositWithInitialAccounts();

        (uint16 currencyId, address rewardToken) = _getCurrencyAndRewardToken();
        CURRENCY_ID = currencyId;
        rewarder = new SecondaryRewarder(
            NOTIONAL,
            currencyId,
            IERC20(rewardToken),
            1e5,
            uint32(block.timestamp + Constants.YEAR)
        );
        owner = NOTIONAL.owner();

        Router.DeployedContracts memory c = getDeployedContracts();
        c.treasury = address(new TreasuryAction(TreasuryAction(c.treasury).COMPTROLLER()));
        upgradeTo(c);

        vm.prank(owner);
        NOTIONAL.setSecondaryIncentiveRewarder(currencyId, rewarder);
    }

    function test_claimRewards_ShouldFailIfNotNotional() public {
        vm.expectRevert("Only Notional");
        rewarder.claimRewards(vm.addr(12321), CURRENCY_ID, 0, 0, 0);
    }
}
