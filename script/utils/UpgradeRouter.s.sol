// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;
pragma abicoder v2;

import "forge-std/Script.sol";

import { GovernanceAction } from "../contracts/external/GovernanceAction.sol";
import { Views } from "../contracts/external/Views.sol";

contract UpgradeRouter is Script {
    NotionalProxy constant NOTIONAL = NotionalProxy(0x1344A36A1B56144C3Bc62E7757377D288fDE0369);
    uint256 NUM_LIBS = 6;

    enum ExternalLib {
        FreeCollateral,
        SettleAssets,
        MigrateIncentives,
        TradingAction,
        nTokenMint,
        nTokenRedeem
    }

    enum ActionContract {
        Governance,
        Views,
        InitializeMarket,
        nTokenAction,
        BatchAction,
        AccountAction,
        ERC1155,
        LiquidateCurrency,
        LiquidatefCash,
        Treasury,
        CalculationViews,
        VaultAction,
        VaultAccountAction,
        VaultLiquidationAction,
        VaultAccountHealth
    }

    function getDeployedLibs() internal view returns (address[] memory libs) {
        libs = new address[](NUM_LIBS);
        Router r = Router(payable(address(NOTIONAL)));
        BatchAction b = BatchAction(r.BATCH_ACTION());

        (
            libs[uint256(ExternalLib.FreeCollateral)],
            libs[uint256(ExternalLib.MigrateIncentives)],
            libs[uint256(ExternalLib.SettleAssetsExternal)],
            libs[uint256(ExternalLib.TradingAction)],
            libs[uint256(ExternalLib.nTokenMintAction)],
            libs[uint256(ExternalLib.nTokenRedeemAction)]
        ) = b.getLibInfo();
    }

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
        c.vaultAction = r.VAULT_ACTION();
        c.vaultAccountAction = r.VAULT_ACCOUNT_ACTION();
        c.vaultLiquidationAction = r.VAULT_LIQUIDATION_ACTION();
        c.vaultAccountHealth = r.VAULT_ACCOUNT_HEALTH();
    }

    function checkDeployedLibs(
        Router.DeployedContracts memory c,
        address[] memory libs
    ) internal view {
        {
            (address fc, address mc) = Views(c.views).getLibInfo();
            require(fc == libs[ExternalLib.FreeCollateral], "Views FC Lib Mismatch");
            require(mc == libs[ExternalLib.MigrateIncentives], "Views MC Lib Mismatch");
        }
        {
            (address nt) = InitializeMarketsAction(c.initializeMarket).getLibInfo();
            require(nt == libs[ExternalLib.nTokenMint], "Init Markets nToken Mint Lib Mismatch");
        }
        {
            (address fc, address mc, address sa) = nTokenAction(c.nTokenAction).getLibInfo();
            require(fc == libs[ExternalLib.FreeCollateral], "nTokenAction FC Lib Mismatch");
            require(mc == libs[ExternalLib.MigrateIncentives], "nTokenAction MC Lib Mismatch");
            require(sa == libs[ExternalLib.SettleAssets], "nTokenAction SA Lib Mismatch");
        }
        {
            (address fc, address mc, address sa, address ta, address nt, address nr) = BatchAction(c.batchAction).getLibInfo();
            require(fc == libs[ExternalLib.FreeCollateral], "BatchAction FC Lib Mismatch");
            require(mc == libs[ExternalLib.MigrateIncentives], "BatchAction MC Lib Mismatch");
            require(sa == libs[ExternalLib.SettleAssets], "BatchAction SA Lib Mismatch");
            require(ta == libs[ExternalLib.TradingAction], "BatchAction TA Lib Mismatch");
            require(nt == libs[ExternalLib.nTokenMint], "BatchAction NT Lib Mismatch");
            require(nr == libs[ExternalLib.nTokenRedeem], "BatchAction NR Lib Mismatch");
        }
        {
            (address fc, address mc, address sa, address nr) = AccountAction(c.accountAction).getLibInfo();
            require(fc == libs[ExternalLib.FreeCollateral], "AccountAction FC Lib Mismatch");
            require(mc == libs[ExternalLib.MigrateIncentives], "AccountAction MC Lib Mismatch");
            require(sa == libs[ExternalLib.SettleAssets], "AccountAction SA Lib Mismatch");
            require(nr == libs[ExternalLib.nTokenRedeem], "AccountAction NR Lib Mismatch");
        }
        {
            (address fc) = ERC1155Action(c.erc1155).getLibInfo();
            require(fc == libs[ExternalLib.FreeCollateral], "ERC1155Action FC Lib Mismatch");
        }
        {
            (address fc, address mc) = LiquidateCurrencyAction(c.liquidateCurrency).getLibInfo();
            require(fc == libs[ExternalLib.FreeCollateral], "LiquidateCurrency FC Lib Mismatch");
            require(mc == libs[ExternalLib.MigrateIncentives], "LiquidateCurrency MC Lib Mismatch");
        }
        {
            (address fc, address sa) = LiquidatefCashAction(c.liquidatefCash).getLibInfo();
            require(fc == libs[ExternalLib.FreeCollateral], "Liquidate fCash FC Lib Mismatch");
            require(sa == libs[ExternalLib.SettleAssets], "Liquidate fCash SA Lib Mismatch");
        }
        {
            (address mc) = CalculationViews(c.calculationViews).getLibInfo();
            require(mc == libs[ExternalLib.MigrateIncentives], "CalculationViews MC Lib Mismatch");
        }
        {
            (address ta) = VaultAction(c.vaultAction).getLibInfo();
            require(ta == libs[ExternalLib.TradingAction], "VaultAction TA Lib Mismatch");
        }
        {
            (address ta) = VaultAccountAction(c.vaultAccountAction).getLibInfo();
            require(ta == libs[ExternalLib.TradingAction], "VaultAccountAction TA Lib Mismatch");
        }
        {
            (address fc, address sa) = VaultLiquidationAction(c.vaultLiquidationAction).getLibInfo();
            require(fc == libs[ExternalLib.FreeCollateral], "Vault Liquidation FC Lib Mismatch");
            require(sa == libs[ExternalLib.SettleAssets], "Vault Liquidation SA Lib Mismatch");
        }
    }

    function _deployContract(
        ActionContract name,
        // This is updated in memory
        Router.DeployedContracts memory c,
        address[] memory libs
    ) private returns (bool upgradePauseRouter) {
        upgradePauseRouter = false;

        if (name == ActionContract.Governance) {
            c.governance = address(new GovernanceAction());
        } else if (name == ActionContract.Views) {
            c.views = address(new Views());
            upgradePauseRouter = true;
        } else if (name == ActionContract.InitializeMarket) {
            c.initializeMarket = address(new InitializeMarketsAction());
        } else if (name == ActionContract.nTokenAction) {
            c.nTokenAction = address(new nTokenAction());
        } else if (name == ActionContract.BatchAction) {
            c.batchAction = address(new BatchAction());
        } else if (name == ActionContract.AccountAction) {
            c.accountAction = address(new AccountAction());
        } else if (name == ActionContract.ERC1155) {
            c.erc1155 = address(new ERC1155Action());
            upgradePauseRouter = true;
        } else if (name == ActionContract.LiquidateCurrency) {
            c.liquidateCurrency = address(new LiquidateCurrencyAction());
            upgradePauseRouter = true;
        } else if (name == ActionContract.LiquidatefCash) {
            c.liquidatefCash = address(new LiquidatefCashAction());
            upgradePauseRouter = true;
        } else if (name == ActionContract.Treasury) {
            // TODO: remove comptroller from constructor
            c.treasury = address(new TreasuryAction(address(0)))
        } else if (name == ActionContract.CalculationViews) {
            c.calculationViews = address(new CalculationViews());
        } else if (name == ActionContract.VaultAction) {
            c.vaultAction = address(new VaultAction());
        } else if (name == ActionContract.VaultAccountAction) {
            c.vaultAccountAction = address(new VaultAccountAction());
        } else if (name == ActionContract.VaultLiquidationAction) {
            c.vaultLiquidationAction = address(new VaultLiquidationAction());
        } else if (name == ActionContract.VaultAccountHealth) {
            c.vaultAccountHealth = address(new VaultAccountHealth());
            upgradePauseRouter = true;
        } else {
            revert("Unknown");
        }
    }

    function _deployLib(
        ExternalLib name,
        address[] memory libs
    ) private {
        if (name == ExternalLib.FreeCollateral) {
            libs[ExternalLib.FreeCollateral] = address(new FreeCollateralExternal());
        } else if (name == ExternalLib.SettleAssets) {
            libs[ExternalLib.SettleAssets] = address(new SettleAssetsExternal());
        } else if (name == ExternalLib.MigrateIncentives) {
            libs[ExternalLib.MigrateIncentives] = address(new MigrateIncentives());
        } else if (name == ExternalLib.TradingAction) {
            libs[ExternalLib.TradingAction] = address(new TradingAction());
        } else if (name == ExternalLib.nTokenMint) {
            libs[ExternalLib.nTokenMint] = address(new nTokenMintAction());
        } else if (name == ExternalLib.nTokenRedeem) {
            libs[ExternalLib.nTokenRedeem] = address(new nTokenRedeemAction());
        }
    }

    function deployRouter(
        ExternalLib[] memory upgradeLib,
        ActionContract[] memory upgradeActions
    ) internal returns (Router r, PauseRouter pr) {
        address[] memory libs = getDeployedLibs();
        Router.DeployedContracts memory c = getDeployedContracts();

        // libs are updated in memory
        for (uint256 i; i < upgradeLib.length; i++) _deployLib(upgradeLib[i], libs);
        
        bool upgradePauseRouter = false;
        for (uint256 i; i < upgradeActions.length; i++) {
            // c is updated in memory
            upgradePauseRouter = upgradePauseRouter || _deployContract(upgradeActions[i], c);
        }

        checkDeployedLibs(c, libs);

        if (upgradePauseRouter) {
            pr = new PauseRouter(
                c.views,
                c.liquidateCurrency,
                c.liquidatefCash,
                c.calculationViews,
                c.vaultAccountHealth
            );
        } else {
            // Gets the current pause router address;
            pr = PauseRouter(Router(address(NOTIONAL)).pauseRouter());
        }

        r = new Router(c);
    }

    function upgradeTo(Router r) internal {
        vm.prank(NOTIONAL.owner());
        NOTIONAL.upgradeTo(address(r));
    }

    function upgradeCalldata(Router r) internal returns (address, bytes memory) {
        return (
            address(NOTIONAL),
            abi.encodeWithSelector(NOTIONAL.upgradeTo.selector, (address(r)))
        );
    }
}