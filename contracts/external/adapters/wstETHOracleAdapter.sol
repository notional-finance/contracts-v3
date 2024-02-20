// SPDX-License-Identifier: BSUL-1.1
pragma solidity =0.7.6;

import "./ChainlinkAdapter.sol";
import "../../math/SafeUint256.sol";

interface WSTETH {
    function tokensPerStEth() external view returns (uint256);
    function stEthPerToken() external view returns (uint256);
}

contract wstETHOracleAdapter is ChainlinkAdapter {
    using SafeUint256 for uint256;

    WSTETH constant wstETH = WSTETH(0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0);

    // This can be used for wstETH/ETH or wstETH/USD
    constructor (
        AggregatorV2V3Interface baseToUSDOracle_,
        bool invertBase_,
        bool invertQuote_,
        string memory description_
    ) ChainlinkAdapter(
        baseToUSDOracle_,
        AggregatorV2V3Interface(address(wstETH)),
        invertBase_,
        invertQuote_,
        description_,
        AggregatorV2V3Interface(address(0))
    ) {
        // This is only valid on mainnet, on other chains there is a chainlink oracle
        // that returns the token rate.
        uint256 id;
        assembly { id := chainid() }
        require(id == 1);
    }

    function _getQuoteRate() internal view override returns (int256 quoteRate) {
        quoteRate = invertQuote ? 
            wstETH.stEthPerToken().toInt() : 
            wstETH.tokensPerStEth().toInt();
    }
}