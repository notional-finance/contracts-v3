// SPDX-License-Identifier: BSUL-1.1
pragma solidity =0.7.6;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Deployments} from "../global/Deployments.sol";

contract MockCToken is ERC20 {
    uint private _answer;
    uint private _supplyRate;
    uint8 internal _decimals;
    address public underlying;
    function decimals() public view override returns (uint8) { return _decimals; }
    event AccrueInterest(uint cashPrior, uint interestAccumulated, uint borrowIndex, uint totalBorrows);

    constructor(uint8 decimals_) ERC20("cMock", "cMock") {
        _decimals = decimals_;
        _mint(msg.sender, type(uint80).max);
    }

    function balanceOfUnderlying(address owner) external view returns (uint256) {
        return (balanceOf(owner) * _answer) / 1e18;
    }

    function setUnderlying(address underlying_) external {
        underlying = underlying_;
    }

    function setAnswer(uint a) external {
        _answer = a;
    }

    function setSupplyRate(uint a) external {
        _supplyRate = a;
    }

    function exchangeRateCurrent() external returns (uint) {
        // This is here to test if we've called the right function
        emit AccrueInterest(0, 0, 0, 0);
        return _answer;
    }

    function exchangeRateStored() external view returns (uint) {
        return _answer;
    }

    function supplyRatePerBlock() external view returns (uint) {
        return _supplyRate;
    }

    function accrualBlockNumber() external view returns (uint256) {
        return block.number;
    }

    function interestRateModel() external pure returns (address) {
        return address(0);
    }

    function mint() external payable {
        _mint(msg.sender, (msg.value * 1e18) / _answer);
    }

    function mint(uint mintAmount) external returns (uint) {
        ERC20(underlying).transferFrom(msg.sender, address(this), mintAmount);
        uint minted = (mintAmount * 1e18) / _answer;
        _mint(msg.sender, minted);

        // This is the error code
        return 0;
    }

    function redeem(uint redeemTokens) external returns (uint) {
        _burn(msg.sender, redeemTokens);
        uint redeemed = (redeemTokens * _answer) / 1e18;
        if (underlying == address(0)) {
            payable(msg.sender).transfer(redeemed);
        } else {
            ERC20(underlying).transfer(msg.sender, redeemed);
        }
        // This is the error code
        return 0;
    }

    function redeemUnderlying(uint redeemAmount) external returns (uint) {
        uint redeemTokens = (redeemAmount * 1e18) / _answer;
        _burn(msg.sender, redeemTokens);
        if (underlying == address(0)) {
            payable(msg.sender).transfer(redeemAmount);
        } else {
            ERC20(underlying).transfer(msg.sender, redeemAmount);
        }
        // This is the error code
        return 0;
    }

    // Not an actual Compound method, but used for testing WETH unwrapping during
    // redemption
    function redeemUnderlyingToWETH(uint redeemAmount) external returns (uint) {
        uint redeemTokens = (redeemAmount * 1e18) / _answer;
        _burn(msg.sender, redeemTokens);
        if (underlying == address(0)) {
            Deployments.WETH.deposit{value: redeemAmount}();
            ERC20(address(Deployments.WETH)).transfer(msg.sender, redeemAmount);
        }
        // This is the error code
        return 0;
    }

    receive() external payable { }
}


contract MockCTokenAssetRateAdapter {
    uint8 public constant decimals = 18;
    MockCToken cToken;

    constructor (MockCToken _cToken) { cToken = _cToken; }

    function getExchangeRateView() external view returns (int256) {
        return int256(cToken.exchangeRateStored());
    }
}
