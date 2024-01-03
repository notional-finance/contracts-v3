// SPDX-License-Identifier: GPL-3.0-only
pragma solidity >=0.7.0;

interface IRouter {
    struct DeployedContracts {
        address governance;
        address views;
        address initializeMarket;
        address nTokenActions;
        address batchAction;
        address accountAction;
        address erc1155;
        address liquidateCurrency;
        address liquidatefCash;
        address treasury;
        address calculationViews;
        address vaultAccountAction;
        address vaultAction;
        address vaultLiquidationAction;
        address vaultAccountHealth;
    }

    function ACCOUNT_ACTION() external view returns (address);
    function BATCH_ACTION() external view returns (address);
    function CALCULATION_VIEWS() external view returns (address);
    function ERC1155() external view returns (address);
    function GOVERNANCE() external view returns (address);
    function INITIALIZE_MARKET() external view returns (address);
    function LIQUIDATE_CURRENCY() external view returns (address);
    function LIQUIDATE_FCASH() external view returns (address);
    function NTOKEN_ACTIONS() external view returns (address);
    function TREASURY() external view returns (address);
    function VAULT_ACCOUNT_ACTION() external view returns (address);
    function VAULT_ACCOUNT_HEALTH() external view returns (address);
    function VAULT_ACTION() external view returns (address);
    function VAULT_LIQUIDATION_ACTION() external view returns (address);
    function VIEWS() external view returns (address);
    function getRouterImplementation(bytes4 sig) external view returns (address);
    function initialize(address owner_, address pauseRouter_, address pauseGuardian_) external;
}
