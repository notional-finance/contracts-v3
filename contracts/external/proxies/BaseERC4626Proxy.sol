// SPDX-License-Identifier: BSUL-1.1
pragma solidity =0.7.6;
pragma abicoder v2;

import {Constants} from "../../global/Constants.sol";
import {Deployments} from "../../global/Deployments.sol";
import {SafeUint256} from "../../math/SafeUint256.sol";
import {SafeInt256} from "../../math/SafeInt256.sol";

import {IERC4626} from "../../../interfaces/IERC4626.sol";
import {NotionalProxy} from "../../../interfaces/notional/NotionalProxy.sol";
import {IERC20 as IERC20WithDecimals} from "../../../interfaces/IERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import {Initializable} from "@openzeppelin/contracts/proxy/Initializable.sol";

interface ITransferEmitter {
    function emitTransfer(address from, address to, uint256 amount) external;
    function emitMintOrBurn(address account, int256 netBalance) external;
    function emitMintTransferBurn(
        address minter, address burner, uint256 mintAmount, uint256 transferAndBurnAmount
    ) external;
    function emitfCashTradeTransfers(
        address account, address nToken, int256 accountToNToken, uint256 cashToReserve
    ) external;
}

/// @notice Each nToken will have its own proxy contract that forwards calls to the main Notional
/// proxy where all the storage is located. There are two types of nToken proxies: regular nToken
/// and staked nToken proxies which both implement ERC20 standards. Each nToken proxy is an upgradeable
/// beacon contract so that methods they proxy can be extended in the future.
/// @dev The first four nTokens deployed (ETH, DAI, USDC, WBTC) have non-upgradeable nToken proxy
/// contracts and are not easily upgraded. This may change in the future but requires a lot of testing
/// and may break backwards compatibility with integrations.
abstract contract BaseERC4626Proxy is IERC20, IERC4626, Initializable, ITransferEmitter {
    using SafeUint256 for uint256;
    using SafeInt256 for int256;

    event ProxyRenamed();

    /*** IMMUTABLES [SET ON IMPLEMENTATION] ***/
    
    /// @notice Inherits from Constants.INTERNAL_TOKEN_PRECISION
    uint8 public constant decimals = 8;

    /// @notice Precision for exchangeRate()
    uint256 public constant EXCHANGE_RATE_PRECISION = 1e18;

    /// @notice Address of the notional proxy, proxies only have access to a subset of the methods
    NotionalProxy public immutable NOTIONAL;

    /*** STORAGE SLOTS [SET ONCE ON EACH PROXY] ***/

    /// @notice Will be "[Staked] nToken {Underlying Token}.name()", therefore "USD Coin" will be
    /// "nToken USD Coin" for the regular nToken and "Staked nToken USD Coin" for the staked version.
    string public name;

    /// @notice Will be "[s]n{Underlying Token}.symbol()", therefore "USDC" will be "nUSDC"
    string public symbol;

    /// @notice Currency id that this nToken refers to
    uint16 public currencyId;

    /// @notice Native underlying decimal places
    uint8 public nativeDecimals;

    /// @notice ERC20 underlying token referred to as the "asset" in IERC4626
    address public underlying;

    /*** END STORAGE SLOTS ***/

    constructor(NotionalProxy notional_
    // Initializer modifier is used here to prevent attackers from re-initializing the
    // implementation. No real attack vector here since there is no ownership modification
    // on the implementation but this is best practice.
    ) initializer { 
        NOTIONAL = notional_;
    }

    modifier onlyNotional() {
        require(msg.sender == address(NOTIONAL), "Unauthorized");
        _;
    }

    function initialize(
        uint16 currencyId_,
        address underlying_,
        string memory underlyingName_,
        string memory underlyingSymbol_
    ) external onlyNotional initializer {
        currencyId = currencyId_;

        (string memory namePrefix, string memory nameSuffix, string memory symbolPrefix) = _getPrefixes();
        name = string(abi.encodePacked(namePrefix, " ", underlyingName_, nameSuffix));
        symbol = string(abi.encodePacked(symbolPrefix, underlyingSymbol_));

        if (underlying_ == Constants.ETH_ADDRESS) {
            // Use WETH for underlying in the case of ETH, no approval to Notional is
            // necessary since WETH is redeemed here
            underlying = address(Deployments.WETH);
        } else {
            underlying = underlying_;
            // Allows Notional to transfer from proxy
            SafeERC20.safeApprove(IERC20(underlying), address(NOTIONAL), type(uint256).max);
        }

        nativeDecimals = IERC20WithDecimals(underlying).decimals();
        require(nativeDecimals < 36);
    }

    function rename(
        string memory underlyingName_,
        string memory underlyingSymbol_
    ) external {
        require(msg.sender == NOTIONAL.owner());
        (string memory namePrefix, string memory nameSuffix, string memory symbolPrefix) = _getPrefixes();
        name = string(abi.encodePacked(namePrefix, " ", underlyingName_, nameSuffix));
        symbol = string(abi.encodePacked(symbolPrefix, underlyingSymbol_));
        emit ProxyRenamed();
    }

    /// @notice Allows ERC20 transfer events to be emitted from the proper address so that
    /// wallet tools can properly track balances.
    function emitTransfer(address from, address to, uint256 amount) external override onlyNotional {
        emit Transfer(from, to, amount);
    }

    /// @notice Convenience method for minting and burning
    function emitMintOrBurn(address account, int256 netBalance) external override onlyNotional {
        if (netBalance < 0) {
            // Burn
            emit Transfer(account, address(0), uint256(netBalance.neg()));
        } else {
            // Mint
            emit Transfer(address(0), account, uint256(netBalance));
        }
    }

    /// @notice Convenience method for mint, transfer and burn. Used in vaults to record margin deposits and
    /// withdraws.
    function emitMintTransferBurn(
        address minter, address burner, uint256 mintAmount, uint256 transferAndBurnAmount
    ) external override onlyNotional {
        emit Transfer(address(0), minter, mintAmount);
        emit Transfer(minter, burner, transferAndBurnAmount);
        emit Transfer(burner, address(0), transferAndBurnAmount);
    }

    /// @notice Only used on pCash when fCash is traded.
    function emitfCashTradeTransfers(
        address account, address nToken, int256 accountToNToken, uint256 cashToReserve
    ) external override onlyNotional {
        if (accountToNToken < 0) {
            emit Transfer(account, nToken, uint256(accountToNToken.abs()));
        } else {
            emit Transfer(nToken, account, uint256(accountToNToken));
        }
        emit Transfer(account, Constants.FEE_RESERVE, cashToReserve);
    }

    /// @notice Returns the asset token reference by IERC4626, uses the underlying token as the asset
    /// for ERC4626 so that it is compatible with more use cases.
    function asset() external override view returns (address) { return underlying; }

    /// @notice Returns the total present value of the assets held in native underlying token precision
    function totalAssets() public override view returns (uint256 totalManagedAssets) {
        totalManagedAssets = _getTotalValueExternal();
    }

    function convertToShares(uint256 assets) public override view returns (uint256 shares) {
        return assets.mul(EXCHANGE_RATE_PRECISION).div(exchangeRate());
    }

    function convertToAssets(uint256 shares) public override view returns (uint256 assets) {
        // Notional truncates balances below the 8th decimal place if they exist, so truncate
        // those balances here as well.
        uint256 truncate = 10 ** (nativeDecimals < 8 ? 0 : nativeDecimals - 8);
        return shares.mul(exchangeRate()).div(EXCHANGE_RATE_PRECISION)
            .div(truncate).mul(truncate);
    }

    /// @notice Gets the max underlying supply
    function maxDeposit(address /*receiver*/) public override view returns (uint256 maxAssets) {
        // Both nTokens and pCash tokens are limited by the max underlying supply
        (
            /* */,
            /* */,
            uint256 maxUnderlyingSupply,
            uint256 currentUnderlyingSupply,
            /* */,
            /* */
        ) = NOTIONAL.getPrimeFactors(currencyId, block.timestamp);

        if (maxUnderlyingSupply == 0) {
            return type(uint256).max;
        } else if (maxUnderlyingSupply <= currentUnderlyingSupply) {
            return 0;
        } else {
            // No overflow here
            return (maxUnderlyingSupply - currentUnderlyingSupply)
                .mul(10 ** nativeDecimals)
                .div(uint256(Constants.INTERNAL_TOKEN_PRECISION));
        }
    }

    /// @notice Gets the max underlying supply and converts it to shares
    function maxMint(address /*receiver*/) external override view returns (uint256 maxShares) {
        uint256 maxAssets = maxDeposit(address(0));
        if (maxAssets == type(uint256).max) return maxAssets;

        return convertToShares(maxAssets);
    }

    function maxRedeem(address owner) external override view returns (uint256 maxShares) {
        return _balanceOf(owner);
    }

    function maxWithdraw(address owner) external override view returns (uint256 maxAssets) {
        return convertToAssets(_balanceOf(owner));
    }

    /// @notice Deposits are based on the conversion rate assets to shares.
    /// @dev Will round down inside convertToShares. Deposits more closely match how
    /// Notional processes minting within the protocol.
    function previewDeposit(uint256 assets) external override view returns (uint256 shares) {
        // Rounds down so that the account receives less shares than assets. This calculation
        // is only used as a view method.
        return convertToShares(assets);
    }

    /// @notice Mints are based on the conversion rate from shares to assets.
    /// @dev Will be called during `mint` to calculate how much assets to transfer. Therefore,
    /// there may be some rounding errors when the number of shares minted does not match what
    /// is requested.
    function previewMint(uint256 shares) public override view returns (uint256 assets) {
        // convertToAssets will also convert the decimal basis to 8 decimal places. To round up,
        // add one to the value with a smaller decimal basis.
        return nativeDecimals < 8 ?
            convertToAssets(shares).add(1) :
            convertToAssets(shares.add(1));
    }

    /// @notice Calculates how much assets will be returned when redeeming the given amount
    /// of shares.
    function previewRedeem(uint256 shares) external view override returns (uint256 assets) {
        // Rounds down so that the account receives less shares than assets. This calculation
        // is only used as a view method.
        return convertToAssets(shares);
    }

    /// @notice Calculates how many shares need to be redeemed to receive the specified amount
    /// of assets.
    function previewWithdraw(uint256 assets) public view override returns (uint256 shares) {
        // convertToShares will also convert the decimal basis to 8 decimal places. To round up,
        // add one to the value with a larger decimal basis.
        return nativeDecimals < 8 ?
            convertToShares(assets.add(1)) :
            convertToShares(assets).add(1);
    }

    /// @notice Deposits assets into Notional and mints either prime cash or nTokens. Unlike the wrapped fCash
    /// proxy this will not hold prime cash assets on the contract and wrap them, the assets will be deposited
    /// directly into the user's account and may be used as collateral.
    /// @dev The proxy contract will first transfer the assets to the contract and then transfer them
    /// to Notional.
    function deposit(uint256 assets, address receiver) external override returns (uint256 shares) {
        uint256 msgValue;
        (assets, msgValue) = _transferAssets(assets);
        shares = _mint(assets, msgValue, receiver);

        emit Transfer(address(0), receiver, shares);
        emit Deposit(msg.sender, receiver, assets, shares);
    }

    /// @notice Similar to deposit, however the amount of shares are specified instead.
    function mint(uint256 shares, address receiver) external override returns (uint256 assets) {
        uint256 msgValue;
        assets = previewMint(shares);
        (assets, msgValue) = _transferAssets(assets);
        
        uint256 shares_ = _mint(assets, msgValue, receiver);

        emit Transfer(address(0), receiver, shares_);
        emit Deposit(msg.sender, receiver, assets, shares_);
    }

    function _transferAssets(uint256 assets) private returns (uint256 assetsActual, uint256 msgValue) {
        // NOTE: this results in double transfer of assets from the msg.sender to the proxy,
        // then from the proxy to Notional
        uint256 balanceBefore = IERC20(underlying).balanceOf(address(this));
        SafeERC20.safeTransferFrom(IERC20(underlying), msg.sender, address(this), assets);
        uint256 balanceAfter = IERC20(underlying).balanceOf(address(this));

        // Get the most accurate accounting of the assets transferred
        assetsActual = balanceAfter.sub(balanceBefore);

        if (currencyId == Constants.ETH_CURRENCY_ID) {
            // Unwrap WETH and set the msgValue
            Deployments.WETH.withdraw(assetsActual);
            msgValue = assetsActual;
        } else {
            msgValue = 0;
        }
    }

    /// @notice Withdraws the asset from Notional and they will be transferred to the receiver.
    function withdraw(uint256 assets, address receiver, address owner) external override returns (uint256 shares) {
        // NOTE: this will return an under-estimated amount for assets so the end amount of assets redeemed will
        // be less than specified.
        shares = previewWithdraw(assets);
        uint256 balance = _balanceOf(owner);
        if (shares > balance) revert("Insufficient Balance");

        // Allowance checks when receiver != owner are done on the Notional proxy
        uint256 assetsFinal = _redeem(shares, receiver, owner);
        emit Transfer(owner, address(0), shares);

        // NOTE: the assets emitted here will be the correct value, but will not match what was provided.
        emit Withdraw(msg.sender, receiver, owner, assetsFinal, shares);
    }

    /// @notice Redeems the asset from Notional and they will be transferred to the receiver.
    function redeem(uint256 shares, address receiver, address owner) external override returns (uint256 assets) {
        // Allowance checks when receiver != owner are done on the Notional proxy
        uint256 assetsFinal = _redeem(shares, receiver, owner);
        emit Transfer(owner, address(0), shares);
        emit Withdraw(msg.sender, receiver, owner, assetsFinal, shares);

        return assetsFinal;
    }

    function exchangeRate() public view returns (uint256 rate) {
        uint256 totalValueExternal = _getTotalValueExternal();
        uint256 supply = _totalSupply();
        // Exchange Rate from token to Underlying in EXCHANGE_RATE_PRECISION is:
        // 1 token = totalValueExternal * EXCHANGE_RATE_PRECISION / totalSupply
        rate = totalValueExternal.mul(EXCHANGE_RATE_PRECISION).div(supply);
    }

    /** Required ERC20 Methods */
    function balanceOf(address account) external view override returns (uint256) {
        return _balanceOf(account);
    }

    function totalSupply() external view override returns (uint256) {
        return _totalSupply();
    }

    function allowance(address account, address spender) external view override returns (uint256) {
        return _allowance(account, spender);
    }

    function approve(address spender, uint256 amount) external override returns (bool ret) {
        ret = _approve(spender, amount);
        if (ret) emit Approval(msg.sender, spender, amount);
    }

    function transfer(address to, uint256 amount) external override returns (bool ret) {
        // Emit transfer preemptively for Emitter parsing logic.
        emit Transfer(msg.sender, to, amount);
        ret = _transfer(to, amount);
        require(ret);
    }

    function transferFrom(address from, address to, uint256 amount) external override returns (bool ret) {
        // Emit transfer preemptively for Emitter parsing logic.
        emit Transfer(from, to, amount);
        ret = _transferFrom(from, to, amount);
        require(ret);
    }

    /** Virtual methods **/
    function _balanceOf(address account) internal view virtual returns (uint256 balance);
    function _totalSupply() internal view virtual returns (uint256 supply);
    function _allowance(address account, address spender) internal view virtual returns (uint256);
    function _approve(address spender, uint256 amount) internal virtual returns (bool);
    function _transfer(address to, uint256 amount) internal virtual returns (bool);
    function _transferFrom(address from, address to, uint256 amount) internal virtual returns (bool);

    /// @notice Hardcoded prefixes for the token name
    function _getPrefixes() internal pure virtual returns (string memory namePrefix, string memory nameSuffix, string memory symbolPrefix);
    function _getTotalValueExternal() internal view virtual returns (uint256 totalValueExternal);
    function _mint(uint256 assets, uint256 msgValue, address receiver) internal virtual returns (uint256 tokensMinted);
    function _redeem(uint256 shares, address receiver, address owner) internal virtual returns (uint256 assets);

    // This is here for safety, but inheriting contracts should never declare storage anyway
    uint256[40] __gap;
}