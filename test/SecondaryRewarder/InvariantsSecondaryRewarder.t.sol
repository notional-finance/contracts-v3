// SPDX-License-Identifier: MIT
pragma solidity >=0.7.6;
pragma abicoder v2;

import {SecondaryRewarderSetupTest} from "./SecondaryRewarderSetupTest.sol";
import {Router} from "../../contracts/external/Router.sol";
import {TokenHandler} from "../../contracts/internal/balances/TokenHandler.sol";
import {BatchAction} from "../../contracts/external/actions/BatchAction.sol";
import {nTokenAction} from "../../contracts/external/actions/nTokenAction.sol";
import {TreasuryAction} from "../../contracts/external/actions/TreasuryAction.sol";
import {AccountAction} from "../../contracts/external/actions/AccountAction.sol";
import {Views} from "../../contracts/external/Views.sol";
import {DateTime} from "../../contracts/internal/markets/DateTime.sol";
import {IERC20} from "../../interfaces/IERC20.sol";
import {Token} from "../../contracts/global/Types.sol";
import {SecondaryRewarder} from "../../contracts/external/adapters/SecondaryRewarder.sol";
import {Constants} from "../../contracts/global/Constants.sol";
import {SafeInt256} from "../../contracts/math/SafeInt256.sol";
import {SafeUint256} from "../../contracts/math/SafeUint256.sol";

abstract contract InvariantsSecondaryRewarder is SecondaryRewarderSetupTest {
    using SafeUint256 for uint256;
    using SafeInt256 for int256;
    using TokenHandler for Token;

    SecondaryRewarder private rewarder;
    address internal owner;
    uint16 internal CURRENCY_ID;
    address internal REWARD_TOKEN;
    address internal NTOKEN;

    struct AccountsData {
        address account;
    }

    address[5] internal accounts = [
        0xD2162F65D5be7533220a4F016CCeCF0f9C1CADB3,
        0xf3A007b9d892Ace8cc3cb77444C3B9e556E263b2,
        0x4357b2A65E8AD9588B8614E8Fe589e518bDa5F2E,
        0xea0B1eeA6d1dFD490b9267c479E3f22049AAFa3B,
        0xA9908242897d282760341e415fcF120Ec15ecaC0
    ];
    uint32 internal emissionRatePerYear;
    uint256 internal incentiveTokenDecimals;
    uint32 internal startTime;
    uint32 internal endTime;

    function _getCurrencyRewardTokenAndForkBlock() internal virtual returns (uint16 currencyId, address rewardToken);

    function _fork() internal virtual {
        vm.createSelectFork(ARBITRUM_RPC_URL, 153925812);
    }

    function setUp() public {
        (uint16 currencyId, address rewardToken) = _getCurrencyRewardTokenAndForkBlock();
        CURRENCY_ID = currencyId;
        REWARD_TOKEN = rewardToken;

        _fork();

        NTOKEN = NOTIONAL.nTokenAddress(currencyId);
        emissionRatePerYear = 2e9;
        incentiveTokenDecimals = 10 ** IERC20(rewardToken).decimals();
        startTime = uint32(block.timestamp);
        endTime = uint32(block.timestamp + Constants.YEAR);
        rewarder = new SecondaryRewarder(
            NOTIONAL,
            currencyId,
            IERC20(rewardToken),
            emissionRatePerYear,
            endTime
        );
        deal(REWARD_TOKEN, address(rewarder), emissionRatePerYear * incentiveTokenDecimals);
        // transfer enough NOTE tokens to NOTIONAL so that tests do not fail for wrong reasons
        deal(0x019bE259BC299F3F653688c7655C87F998Bc7bC1, address(NOTIONAL), 1e24);
        owner = NOTIONAL.owner();

        Router.DeployedContracts memory c = getDeployedContracts();
        c.batchAction = address(new BatchAction());
        c.accountAction = address(new AccountAction());
        c.treasury = address(new TreasuryAction());
        c.nTokenActions = address(new nTokenAction());
        c.views = address(new Views());
        upgradeTo(c);

        vm.prank(owner);
        NOTIONAL.setSecondaryIncentiveRewarder(currencyId, rewarder);
    }

    function _redeem(address account, uint256 amount) internal {
        uint256 maxAmount = IERC20(NTOKEN).balanceOf(account);
        // if min is less "Insufficient free collateral" error is thrown for DAI-ARB pair
        uint256 minAmount = 3;
        if (maxAmount < minAmount) return;
        amount = bound(amount, minAmount, maxAmount);

        vm.prank(account);
        NOTIONAL.nTokenRedeem(account, CURRENCY_ID, uint96(amount), true, true);
    }

    function _deposit(address account, uint256 amount) internal {
        (,, uint256 maxSupply, uint256 totalSupply,,) = NOTIONAL.getPrimeFactors(CURRENCY_ID, block.timestamp);
        maxSupply = maxSupply * 999 / 1000;
        if (maxSupply == 0 || maxSupply < totalSupply) {
            return;
        }
        (, Token memory token) = NOTIONAL.getCurrency(CURRENCY_ID);
        uint256 max = maxSupply - totalSupply;

        uint256 min = 1e6;
        if (max < min) {
            return;
        }
        amount = bound(amount, min, max);
        amount = uint256(token.convertToExternal(int256(amount)));

        _depositAndMintNToken(CURRENCY_ID, account, amount);
    }

    function _manualClaim(address account) public {
        vm.prank(account);
        NOTIONAL.nTokenClaimIncentives();
    }

    function _transferNToken(address account, uint8 transferTo, uint256 amount) public {
        transferTo = uint8(bound(uint256(transferTo), 0, 6));
        address to;
        if (4 < transferTo) to = vm.addr(52093458702934); // some random address
        else to = accounts[transferTo];
        if (to == account) return;

        uint256 maxAmount = IERC20(NTOKEN).balanceOf(account);
        // Reduce the max transfer amount to avoid potential FC issues here
        amount = bound(amount, 0, maxAmount / 5);
        if (amount == 0) return;

        vm.prank(account);
        IERC20(NTOKEN).transfer(to, amount);
    }

    // maxClaim = emission rate * time period / year
    uint256 constant NUM_SAMPLES = 100;
    function testFuzz_invariant_NoMaterWhatHappensTotalClaimsLeMaxClaim(
        uint256[NUM_SAMPLES][5] memory depositAmounts,
        uint256[NUM_SAMPLES][5] memory redeemAmounts,
        uint32[NUM_SAMPLES] memory skipTimes,
        bool[NUM_SAMPLES][5] memory shouldDeposit,
        bool[NUM_SAMPLES][5] memory shouldRedeem,
        bool[NUM_SAMPLES][5] memory shouldManualClaim,
        bool[NUM_SAMPLES][5] memory shouldTransfer,
        uint8[NUM_SAMPLES][5] memory transferTo,
        uint256[NUM_SAMPLES][5] memory transferAmounts
    ) public {
        uint256 nextSettlementDate = DateTime.getReferenceTime(block.timestamp) + Constants.QUARTER;
        uint256 rewardBalanceAtStart = IERC20(REWARD_TOKEN).balanceOf(address(rewarder));

        for (uint256 i = 0; i < NUM_SAMPLES; i++) {
            skip(bound(skipTimes[i], 0, uint256(7 weeks)));
            if (nextSettlementDate <= block.timestamp) {
                nextSettlementDate += Constants.QUARTER;
                NOTIONAL.initializeMarkets(CURRENCY_ID, false);
                for (uint256 j = 0; j < accounts.length; j++) {
                    NOTIONAL.settleAccount(accounts[j]);
                }
            }

            for (uint256 j = 0; j < accounts.length; j++) {
                address account = accounts[j];
                if (shouldDeposit[j][i]) {
                    _deposit(account, depositAmounts[j][i]);
                }
                if (shouldRedeem[j][i]) {
                    _redeem(account, redeemAmounts[j][i]);
                }
                if (shouldManualClaim[j][i]) {
                    _manualClaim(account);
                }
                if (shouldTransfer[j][i]) {
                    _transferNToken(account, transferTo[j][i], transferAmounts[j][i]);
                }
            }
            uint256 newRewarderBalance = IERC20(REWARD_TOKEN).balanceOf(address(rewarder));
            uint256 maxClaimableRewards = SafeInt256.min(
                int256(block.timestamp - startTime), int256(endTime - startTime)
            ).toUint().mul(emissionRatePerYear).mul(incentiveTokenDecimals).div(Constants.YEAR);

            uint256 totalClaimed = rewardBalanceAtStart - newRewarderBalance;

            assertLe(totalClaimed, maxClaimableRewards, "Claimed too much.");
        }
        // test that at least something was claim so we are sure tests are actually working
        uint256 rewardBalanceAtEnd = IERC20(REWARD_TOKEN).balanceOf(address(rewarder));
        assertLe(rewardBalanceAtEnd, rewardBalanceAtStart, "Nothing was claimed.");
    }
}

contract InvariantsSecondaryRewarderCbEthArb is InvariantsSecondaryRewarder {
    function _getCurrencyRewardTokenAndForkBlock()
        internal
        pure
        override
        returns (uint16 currencyId, address rewardToken)
    {
        currencyId = 9;
        rewardToken = 0x912CE59144191C1204E64559FE8253a0e49E6548;
    }

    function _fork() internal override {
        vm.createSelectFork(ARBITRUM_RPC_URL, 145559028); // CbEth deployment time
        _initializeMarket(CURRENCY_ID);
    }
}

contract InvariantsSecondaryRewarderDaiArb is InvariantsSecondaryRewarder {
    function _getCurrencyRewardTokenAndForkBlock()
        internal
        pure
        override
        returns (uint16 currencyId, address rewardToken)
    {
        currencyId = 4;
        rewardToken = 0x912CE59144191C1204E64559FE8253a0e49E6548;
    }
}

contract InvariantsSecondaryRewarderUSDCArb is InvariantsSecondaryRewarder {
    function _getCurrencyRewardTokenAndForkBlock()
        internal
        pure
        override
        returns (uint16 currencyId, address rewardToken)
    {
        currencyId = 3;
        rewardToken = 0x912CE59144191C1204E64559FE8253a0e49E6548;
    }
}

contract InvariantsSecondaryRewarderCbEthLido is InvariantsSecondaryRewarder {
    function _getCurrencyRewardTokenAndForkBlock()
        internal
        pure
        override
        returns (uint16 currencyId, address rewardToken)
    {
        currencyId = 9;
        rewardToken = 0x13Ad51ed4F1B7e9Dc168d8a00cB3f4dDD85EfA60;
    }
}

contract InvariantsSecondaryRewarderEthArb is InvariantsSecondaryRewarder {
    function _getCurrencyRewardTokenAndForkBlock()
        internal
        pure
        override
        returns (uint16 currencyId, address rewardToken)
    {
        currencyId = 1;
        rewardToken = 0x912CE59144191C1204E64559FE8253a0e49E6548;
    }
}

contract InvariantsSecondaryRewarderEthUSDC is InvariantsSecondaryRewarder {
    function _getCurrencyRewardTokenAndForkBlock()
        internal
        pure
        override
        returns (uint16 currencyId, address rewardToken)
    {
        currencyId = 1;
        rewardToken = 0xaf88d065e77c8cC2239327C5EDb3A432268e5831;
    }
}