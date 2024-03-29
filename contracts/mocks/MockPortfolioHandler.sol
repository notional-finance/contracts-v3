// SPDX-License-Identifier: BSUL-1.1
pragma solidity =0.7.6;
pragma abicoder v2;

import "../internal/Emitter.sol";
import "../internal/AccountContextHandler.sol";
import "../internal/portfolio/PortfolioHandler.sol";
import "../global/StorageLayoutV1.sol";

contract MockPortfolioHandler is StorageLayoutV1 {
    using PortfolioHandler for PortfolioState;
    using AccountContextHandler for AccountContext;

    event TransferBatch(
        address indexed operator,
        address indexed from,
        address indexed to,
        uint256[] ids,
        uint256[] values
    );

    function getAssetArray(address account) external view returns (PortfolioAsset[] memory) {
        AccountContext memory accountContext = AccountContextHandler.getAccountContext(account);
        return PortfolioHandler.getSortedPortfolio(account, accountContext.assetArrayLength);
    }

    function addAsset(
        PortfolioState memory portfolioState,
        uint16 currencyId,
        uint256 maturity,
        uint256 assetType,
        int256 notional
    ) public pure returns (PortfolioState memory) {
        portfolioState.addAsset(currencyId, maturity, assetType, notional);

        return portfolioState;
    }

    function getAccountContext(address account) external view returns (AccountContext memory) {
        return AccountContextHandler.getAccountContext(account);
    }

    function storeAssets(address account, PortfolioState memory portfolioState)
        public
        returns (AccountContext memory)
    {
        AccountContext memory accountContext = AccountContextHandler.getAccountContext(account);
        accountContext.storeAssetsAndUpdateContext(account, portfolioState);
        accountContext.setAccountContext(account);

        return accountContext;
    }

    function deleteAsset(PortfolioState memory portfolioState, uint256 index)
        public
        pure
        returns (PortfolioState memory)
    {
        portfolioState.deleteAsset(index);

        return portfolioState;
    }

    function buildPortfolioState(address account, uint256 newAssetsHint)
        public
        view
        returns (PortfolioState memory)
    {
        AccountContext memory accountContext = AccountContextHandler.getAccountContext(account);

        return
            PortfolioHandler.buildPortfolioState(
                account,
                accountContext.assetArrayLength,
                newAssetsHint
            );
    }

    function negChange(int256 start, int256 end) external pure returns (int256) {
        return SafeInt256.negChange(start, end);
    }

    function decodefCashId(uint256 id) external pure returns (uint16 currencyId, uint256 maturity, bool isfCashDebt) {
        return Emitter.decodefCashId(id);
    }
}
