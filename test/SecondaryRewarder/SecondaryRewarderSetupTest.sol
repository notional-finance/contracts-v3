// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;
pragma abicoder v2;

import {Test} from "forge-std/Test.sol";

import {NotionalProxy} from "../../interfaces/notional/NotionalProxy.sol";
import {Router} from "../../contracts/external/Router.sol";
import {BalanceAction, DepositActionType, Token} from "../../contracts/global/Types.sol";
import {IERC20} from "../../interfaces/IERC20.sol";

contract SecondaryRewarderSetupTest is Test {
    NotionalProxy public constant NOTIONAL = NotionalProxy(0x1344A36A1B56144C3Bc62E7757377D288fDE0369);
    string public ARBITRUM_RPC_URL = vm.envString("ARBITRUM_RPC_URL");
    uint256 private ARBITRUM_FORK_BLOCK = 152642413;

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
        vm.prank(NOTIONAL.owner());
        NOTIONAL.upgradeTo(address(r));
    }

    function defaultFork() internal {
        vm.createSelectFork(ARBITRUM_RPC_URL, ARBITRUM_FORK_BLOCK);
    }

    function _depositAndMintNToken(uint16 currencyId, address account, uint256 amount) internal {
        BalanceAction[] memory balanceActions = new BalanceAction[](1);
        BalanceAction memory balanceAction =
            BalanceAction(DepositActionType.DepositUnderlyingAndMintNToken, currencyId, amount, 0, false, true);
        balanceActions[0] = balanceAction;

        (, Token memory underlyingToken) = NOTIONAL.getCurrency(currencyId);

        vm.startPrank(account);
        if (underlyingToken.tokenAddress == address(0)) {
            deal(account, amount);
            (bool status,) = address(NOTIONAL).call{value: amount}(
                abi.encodeWithSelector(NOTIONAL.batchBalanceAction.selector, account, balanceActions)
            );
            require(status, "Eth DepositUnderlyingAndMintNToken failed");
        } else {
            deal(underlyingToken.tokenAddress, account, amount);
            IERC20(underlyingToken.tokenAddress).approve(address(NOTIONAL), amount);
            NOTIONAL.batchBalanceAction(account, balanceActions);
        }
        vm.stopPrank();
    }

    function _redeemNToken(uint16 currencyId, address account, uint256 amount) internal {
        BalanceAction[] memory balanceActions = new BalanceAction[](1);
        BalanceAction memory balanceAction =
            BalanceAction(DepositActionType.RedeemNToken, currencyId, amount, 0, false, true);
        balanceActions[0] = balanceAction;

        vm.startPrank(account);
        NOTIONAL.batchBalanceAction(account, balanceActions);
        vm.stopPrank();
    }

    function _initializeMarket(uint16 currencyId) internal {
        address fundingAccount = 0x7d7935EDd4b6cDB5f34B0E1cCEAF85a3C4A11254;
        _depositAndMintNToken(currencyId, fundingAccount, 0.05e18);

        vm.startPrank(fundingAccount);
        NOTIONAL.initializeMarkets(currencyId, true);
        vm.stopPrank();
    }
}