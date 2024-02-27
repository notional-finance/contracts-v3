
// SPDX-License-Identifier: BSUL-1.1
pragma solidity =0.7.6;
pragma abicoder v2;

import "../../global/StorageLayoutV2.sol";
import "../../proxy/nProxy.sol";
import "./BasePatchFixRouter.sol";

contract MigrateUSDC_AddressToCurrencyId is StorageLayoutV2, BasePatchFixRouter {
    address public constant USDC = 0xaf88d065e77c8cC2239327C5EDb3A432268e5831;
    address public constant USDC_E = 0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8;
    address payable constant proxy = 0x1344A36A1B56144C3Bc62E7757377D288fDE0369;
    uint16 constant USDC_CURRENCY_ID = 3;

    constructor() BasePatchFixRouter(
        nProxy(proxy).getImplementation(),
        nProxy(proxy).getImplementation(),
        NotionalProxy(proxy)
    ) {}

    function _patchFix() internal override {
        // Updates the reverse mapping of the tokenAddressToCurrencyId
        delete tokenAddressToCurrencyId[USDC_E];
        tokenAddressToCurrencyId[USDC] = USDC_CURRENCY_ID;
    }
}