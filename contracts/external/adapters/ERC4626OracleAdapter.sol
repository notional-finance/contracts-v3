// SPDX-License-Identifier: BSUL-1.1
pragma solidity =0.7.6;

import "../../../interfaces/IERC4626.sol";
import "../../../interfaces/IERC20.sol";
import "../../math/SafeUint256.sol";
import "./ChainlinkAdapter.sol";

contract ERC4626OracleAdapter is ChainlinkAdapter {
    int256 immutable ASSET_PRECISION;
    using SafeInt256 for int256;
    using SafeUint256 for uint256;

    constructor (
        AggregatorV2V3Interface baseToUSDOracle_,
        AggregatorV2V3Interface quoteToUSDOracle_,
        bool invertBase_,
        bool invertQuote_,
        string memory description_,
        AggregatorV2V3Interface sequencerUptimeOracle_
    ) ChainlinkAdapter(
        baseToUSDOracle_, quoteToUSDOracle_, invertBase_, invertQuote_, description_, sequencerUptimeOracle_
    ) {
        uint256 assetDecimals = IERC20(IERC4626(address(quoteToUSDOracle_)).asset()).decimals();
        require(assetDecimals <= 18);
        ASSET_PRECISION = int256(10 ** assetDecimals);
    }
    
    function _getQuoteRate() internal view override returns (int256 quoteRate) {
        // quoteToUSDDecimals will be equal to 1 share of the ERC4626 token.
        // ASSET_PRECISION is equal to 1 asset token. This is returned as: ASSET/SHARE
        IERC4626 oracle = IERC4626(address(quoteToUSDOracle));
        quoteRate = invertQuote ? 
            oracle.convertToShares(uint256(ASSET_PRECISION)).toInt()
                .mul(ASSET_PRECISION).div(quoteToUSDDecimals) :
            oracle.convertToAssets(uint256(quoteToUSDDecimals)).toInt()
                .mul(quoteToUSDDecimals).div(ASSET_PRECISION);
    }
}