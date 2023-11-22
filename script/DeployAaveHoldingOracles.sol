// SPDX-License-Identifier: GPL-3.0-only
pragma solidity >=0.7.6;
pragma abicoder v2;

import {Script} from "forge-std/Script.sol";

import {AaveV3HoldingsOracle} from "../contracts/external/pCash/AaveV3HoldingsOracle.sol";
import {IPrimeCashHoldingsOracle} from "../interfaces/notional/IPrimeCashHoldingsOracle.sol";
import {NotionalProxy} from "../interfaces/notional/NotionalProxy.sol";
import {IAavePool} from "../interfaces/aave/IAavePool.sol";

contract DeployAaveHoldingOracles is Script {
    function run() external {
        string memory json = vm.readFile("v3.arbitrum-one.json");
        NotionalProxy NOTIONAL = NotionalProxy(address(vm.parseJsonAddress(json, ".notional")));
        address AAVE_LENDING_POOL = address(vm.parseJsonAddress(json, ".aaveLendingPool"));
        address POOL_DATA_PROVIDER = address(vm.parseJsonAddress(json, ".aavePoolDataProvider"));

        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        uint16 currencyId = uint16(vm.envUint("DEPLOY_CURRENCY_ID"));

        require(0 < currencyId && currencyId <= NOTIONAL.getMaxCurrencyId(), "Wrong currency id");

        address underlying = IPrimeCashHoldingsOracle(NOTIONAL.getPrimeCashHoldingsOracle(currencyId)).underlying();
        address aToken = IAavePool(AAVE_LENDING_POOL).getReserveData(underlying).aTokenAddress;

        require(aToken != address(0), "Token not supported");

        IPrimeCashHoldingsOracle newOracle =
            new AaveV3HoldingsOracle(NOTIONAL, underlying, AAVE_LENDING_POOL, aToken, POOL_DATA_PROVIDER);

        NOTIONAL.updatePrimeCashHoldingsOracle(currencyId, newOracle);

        vm.stopBroadcast();
    }
}