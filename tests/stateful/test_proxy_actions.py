import brownie
import pytest
from brownie import nBeaconProxy, Contract, EmptyProxy, PrimeCashProxy, PrimeDebtProxy, MockERC20, interface
from brownie.network.state import Chain
from brownie.test import given, strategy
from tests.helpers import initialize_environment
from tests.stateful.invariants import check_system_invariants

WETH9 = interface.WETH9

chain = Chain()

@pytest.fixture(scope="module", autouse=True)
def environment(accounts):
    env = initialize_environment(accounts)
    env.notional.depositUnderlyingToken(accounts[0], 1, 100e18, {"value": 100e18, "from": accounts[0]})
    return env

@pytest.fixture(autouse=True)
def isolation(fn_isolation):
    pass

def getProxy(environment, useNToken):
    if useNToken:
        return environment.nToken[1]
    else:
        return Contract.from_abi('pETH', environment.notional.pCashAddress(1), PrimeCashProxy.abi)

@given(useNToken=strategy("bool"))
def test_cannot_emit_unless_notional(environment, accounts, useNToken):
    proxy = getProxy(environment, useNToken)

    with brownie.reverts("Unauthorized"):
        proxy.emitTransfer(accounts[1], accounts[2], 100e8, {"from": accounts[1]})

    with brownie.reverts("Unauthorized"):
        proxy.emitMintOrBurn(accounts[1], 100e8, {"from": accounts[1]})

    with brownie.reverts("Unauthorized"):
        proxy.emitMintTransferBurn(accounts[1], accounts[1], 100e8, 100e8, {"from": accounts[1]})

    with brownie.reverts("Unauthorized"):
        proxy.emitfCashTradeTransfers(accounts[1], accounts[2], 100e8, 10e8, {"from": accounts[1]})
    
    txn = proxy.emitTransfer(accounts[1], accounts[2], 100e8, {"from": environment.notional})
    assert 'Transfer' in txn.events

def test_cannot_rename_unless_owner(environment, accounts):
    proxy = getProxy(environment, False)

    with brownie.reverts():
        proxy.rename("a", "b", {"from": accounts[1]})
    
    proxy.rename("a", "a", {"from": accounts[0]})
    assert proxy.name() == "Prime a"
    assert proxy.symbol() == "pa"

    proxy = Contract.from_abi('pETH', environment.notional.pDebtAddress(1), PrimeDebtProxy.abi)

    with brownie.reverts():
        proxy.rename("a", "b", {"from": accounts[1]})
    
    proxy.rename("a", "a", {"from": accounts[0]})
    assert proxy.name() == "Prime a Debt"
    assert proxy.symbol() == "pda"

@given(useNToken=strategy("bool"))
def test_cannot_reinitialize_proxy(environment, useNToken, accounts):
    proxy = getProxy(environment, useNToken)
    with brownie.reverts():
        proxy.initialize(2, proxy.address, "test", "test", {"from": accounts[0]})

    beacon = Contract.from_abi('beacon', proxy.address, nBeaconProxy.abi)
    impl = Contract.from_abi('impl', beacon.getImplementation(), PrimeCashProxy.abi)

    # Also cannot call initialize on the implementation
    with brownie.reverts("Unauthorized"):
        impl.initialize(2, proxy.address, "test", "test", {"from": accounts[0]})

    with brownie.reverts("Initializable: contract is already initialized"):
        impl.initialize(2, proxy.address, "test", "test", {"from": environment.notional})

@given(useNToken=strategy("bool"))
def test_upgrade_pcash_proxy(environment, accounts, useNToken):
    proxy = getProxy(environment, useNToken)
    emptyImpl = EmptyProxy.deploy(accounts[0], {"from": accounts[0]})

    proxyEnum = 0 if useNToken else 1
    with brownie.reverts():
        environment.notional.upgradeBeacon(proxyEnum, emptyImpl, {"from": accounts[1]})

    txn = environment.notional.upgradeBeacon(proxyEnum, emptyImpl, {"from": environment.notional.owner()})
    assert txn.events['Upgraded']['implementation'] == emptyImpl.address

    # this method no longer exists
    with brownie.reverts():
        proxy.balanceOf(accounts[0])

    # Other proxy is unaffected
    assert getProxy(environment, not useNToken).balanceOf(accounts[1]) == 0

def test_cannot_call_proxy_actions_directly(environment, accounts):
    with brownie.reverts():
        environment.notional.nTokenTransferApprove(
            1, accounts[2], accounts[1], 2 ** 255, {"from": accounts[1]}
        )

    with brownie.reverts():
        environment.notional.pCashTransferApprove(
            1, accounts[2], accounts[1], 2 ** 255, {"from": accounts[1]}
        )

    with brownie.reverts():
        environment.notional.nTokenTransfer(
            1, accounts[2], accounts[1], 100e8, {"from": accounts[1]}
        )

    with brownie.reverts():
        environment.notional.pCashTransfer(
            1, accounts[2], accounts[1], 100e8, {"from": accounts[1]}
        )

    with brownie.reverts():
        environment.notional.nTokenTransferFrom(
            1, accounts[2], accounts[1], accounts[0], 100e8, {"from": accounts[1]}
        )

    with brownie.reverts():
        environment.notional.pCashTransferFrom(
            1, accounts[2], accounts[1], accounts[0], 100e8, {"from": accounts[1]}
        )

@given(useNToken=strategy("bool"))
def test_transfer_self_failure(environment, accounts, useNToken):
    proxy = getProxy(environment, useNToken)

    with brownie.reverts():
        proxy.transfer(accounts[0], 1, {"from": accounts[0]})

    with brownie.reverts():
        proxy.transferFrom(accounts[0], accounts[0], 1, {"from": accounts[0]})

@given(useNToken=strategy("bool"))
def test_cannot_transfer_to_system_account(environment, accounts, useNToken):
    proxy = getProxy(environment, useNToken)
    with brownie.reverts():
        proxy.transfer(environment.notional.address, 1e8, {"from": accounts[0]})

@given(useNToken=strategy("bool"))
def test_set_transfer_allowance(environment, accounts, useNToken):
    proxy = getProxy(environment, useNToken)
    proxy.approve(accounts[1], 100e8, {"from": accounts[0]})
    assert proxy.allowance(accounts[0], accounts[1]) == 100e8

    with brownie.reverts("Insufficient allowance"):
        proxy.transferFrom(accounts[0], accounts[2], 101e8, {"from": accounts[1]})

    proxy.transferFrom(accounts[0], accounts[2], 100e8, {"from": accounts[1]})
    assert proxy.allowance(accounts[0], accounts[1]) == 0
    assert proxy.balanceOf(accounts[2]) == 100e8

@given(useNToken=strategy("bool"))
def test_transfer_tokens(environment, accounts, useNToken):
    proxy = getProxy(environment, useNToken)
    balance = proxy.balanceOf(accounts[0])

    if useNToken:
        with brownie.reverts("Neg nToken"):
            proxy.transfer(accounts[1], balance + 1, {"from": accounts[0]})
    else:
        with brownie.reverts("Insufficient balance"):
            proxy.transfer(accounts[1], balance + 1, {"from": accounts[0]})

    proxy.transfer(accounts[2], 100e8, {"from": accounts[0]})
    assert proxy.balanceOf(accounts[2]) == 100e8

def test_cannot_transfer_and_incur_debt(environment, accounts):
    # only applies to pCash
    proxy = getProxy(environment, False)

    balance = proxy.balanceOf(accounts[0])
    environment.notional.enablePrimeBorrow(True, {"from": accounts[0]})
    environment.notional.withdraw(1, balance + 5e8, True, {"from": accounts[0]})

    assert pytest.approx(environment.notional.getAccountBalance(1, accounts[0])['cashBalance'], abs=1000) == -5e8
    assert proxy.balanceOf(accounts[0]) == 0

    # Reverts because balance is negative
    with brownie.reverts("Insufficient balance"):
        proxy.transfer(accounts[1],  1e8, {"from": accounts[0]})

@given(useNToken=strategy("bool"))
def test_transfer_negative_fc_failure(environment, accounts, useNToken):
    proxy = getProxy(environment, useNToken)
    proxy.transfer(accounts[2], 5000e8, {"from": accounts[0]})

    environment.notional.enablePrimeBorrow(True, {"from": accounts[2]})
    # Now we have some debt
    environment.notional.withdraw(2, 5000e8, True, {"from": accounts[2]})

    with brownie.reverts("Insufficient free collateral"):
        proxy.transfer(accounts[0], 5000e8, {"from": accounts[2]})

    # Does allow a smaller transfer
    proxy.transfer(accounts[0], 500e8, {"from": accounts[2]})

@given(useNToken=strategy("bool"))
def test_total_supply_and_value(environment, accounts, useNToken):
    proxy = getProxy(environment, useNToken)
    totalSupply = proxy.totalSupply()
    totalAssets = proxy.totalAssets()

    if useNToken:
        assert totalSupply == environment.notional.getNTokenAccount(proxy.address)['totalSupply']
        assert totalAssets == environment.notional.nTokenPresentValueUnderlyingDenominated(proxy.currencyId()) * 1e18 / 1e8
    else:
        (_, factors, _, totalUnderlying, _, _) = environment.notional.getPrimeFactors(proxy.currencyId(), chain.time())
        assert totalSupply == factors['totalPrimeSupply']
        assert pytest.approx(totalAssets, abs=5) == totalUnderlying * 1e18 / 1e8


@given(useNToken=strategy("bool"))
def test_erc4626_convert_to_shares_and_assets(environment, accounts, useNToken):
    proxy = getProxy(environment, useNToken)
    shares = proxy.convertToShares(1e18)
    assets = proxy.convertToAssets(shares)

    assert assets == 1e18
    assert proxy.previewDeposit(assets) == shares
    assert proxy.previewMint(shares) == assets

@given(useNToken=strategy("bool"))
def test_transfer_above_supply_cap(environment, accounts, useNToken):
    proxy = getProxy(environment, useNToken)
    (_, factors, _, _, _, _) = environment.notional.getPrimeFactors(proxy.currencyId(), chain.time())
    environment.notional.setMaxUnderlyingSupply(1, factors['lastTotalUnderlyingValue'] - 100e8, 100)
    
    # Assert cap is in effect
    with brownie.reverts("Over Supply Cap"):
        environment.notional.depositUnderlyingToken(accounts[0], 1, 100e18, {"value": 100e18, "from": accounts[0]})

    # Can still transfer above cap
    proxy.transfer(accounts[2], 100e8, {"from": accounts[0]})

@given(useNToken=strategy("bool"))
def test_max_mint_and_deposit_respects_supply_cap(environment, accounts, useNToken):
    proxy = getProxy(environment, useNToken)

    # No cap means unlimited mint
    assert proxy.maxDeposit(accounts[0]) == 2 ** 256 - 1
    assert proxy.maxMint(accounts[0]) == 2 ** 256 - 1

    (_, factors, _, _, _, _) = environment.notional.getPrimeFactors(proxy.currencyId(), chain.time())
    environment.notional.setMaxUnderlyingSupply(1, factors['lastTotalUnderlyingValue'], 100)

    assert proxy.maxDeposit(accounts[0]) == 0
    assert proxy.maxMint(accounts[0]) == 0

    cap = factors['lastTotalUnderlyingValue'] + 100e8
    environment.notional.setMaxUnderlyingSupply(1, cap, 100)

    assert pytest.approx(proxy.maxDeposit(accounts[0]), rel=1e-6) == 100e18
    assert pytest.approx(proxy.maxMint(accounts[0]), rel=1e-6) == 5000e8

@given(useNToken=strategy("bool"))
def test_max_redeem_and_withdraw_respects_balance(environment, accounts, useNToken):
    proxy = getProxy(environment, useNToken)

    assert proxy.maxWithdraw(accounts[0]) == proxy.convertToAssets(proxy.balanceOf(accounts[0]))
    assert proxy.maxRedeem(accounts[0]) == proxy.balanceOf(accounts[0])

    assert proxy.maxWithdraw(accounts[1]) == 0
    assert proxy.maxRedeem(accounts[1]) == 0

@given(
    currencyId=strategy("uint", min_value=1, max_value=3),
    useReceiver=strategy("bool")
)
def test_deposit(environment, accounts, currencyId, useReceiver):
    proxy = Contract.from_abi('pETH', environment.notional.pCashAddress(currencyId), PrimeCashProxy.abi)
    erc20 = Contract.from_abi("erc20", proxy.asset(), MockERC20.abi)
    decimals = erc20.decimals()

    if currencyId == 1:
        weth = Contract.from_abi("WETH", erc20.address, WETH9.abi)
        weth.deposit({"from": accounts[1], "value": 1e18})

    erc20.approve(proxy, 2 ** 255 - 1, {"from": accounts[1]})
    depositAmount = 10 ** decimals
    assets = proxy.previewDeposit(depositAmount)

    receiver = accounts[2] if useReceiver else accounts[1]

    balanceBefore = erc20.balanceOf(accounts[1])
    proxy.deposit(depositAmount, receiver, {"from": accounts[1]})
    balanceAfter = erc20.balanceOf(accounts[1])

    minted = proxy.balanceOf(receiver)
    assert assets == minted
    (cashBalance, _, _) = environment.notional.getAccountBalance(currencyId, receiver)
    assert cashBalance == minted
    assert pytest.approx(balanceBefore - balanceAfter, rel=1e-6, abs=100) == depositAmount

    check_system_invariants(environment, accounts)

@given(
    currencyId=strategy("uint", min_value=1, max_value=3),
    useReceiver=strategy("bool")
)
def test_mint(environment, accounts, currencyId, useReceiver):
    proxy = Contract.from_abi('pETH', environment.notional.pCashAddress(currencyId), PrimeCashProxy.abi)
    erc20 = Contract.from_abi("erc20", proxy.asset(), MockERC20.abi)
    decimals = erc20.decimals()

    if currencyId == 1:
        weth = Contract.from_abi("WETH", erc20.address, WETH9.abi)
        weth.deposit({"from": accounts[1], "value": 1e18 + 1e10})

    erc20.approve(proxy, 2 ** 255 - 1, {"from": accounts[1]})
    depositAmount = 10 ** decimals
    shares = proxy.previewDeposit(depositAmount)

    receiver = accounts[2] if useReceiver else accounts[1]

    balanceBefore = erc20.balanceOf(accounts[1])
    proxy.mint(shares, receiver, {"from": accounts[1]})
    balanceAfter = erc20.balanceOf(accounts[1])

    minted = proxy.balanceOf(receiver)
    assert shares == minted

    (cashBalance, _, _) = environment.notional.getAccountBalance(currencyId, receiver)
    assert cashBalance == minted
    assert pytest.approx(balanceBefore - balanceAfter, rel=1e-6, abs=100) == depositAmount
    assert (balanceBefore - balanceAfter) >= depositAmount

    check_system_invariants(environment, accounts)

def test_mint_or_deposit_above_cap_fails(environment, accounts):
    factors = environment.notional.getPrimeFactors(3, chain.time() + 1)
    # Have to buffer the max supply a bit to ensure that interest accrual does not
    # push this over the cap immediately
    maxSupply = factors['factors']['lastTotalUnderlyingValue'] + 0.1e8
    environment.notional.setMaxUnderlyingSupply(3, maxSupply, 70)
    factors = environment.notional.getPrimeFactors(3, chain.time() + 1)

    environment.notional.enablePrimeBorrow(True, {"from": accounts[0]})

    # Can borrow up to debt cap
    maxPrimeCash = environment.notional.convertUnderlyingToPrimeCash(3, factors['maxUnderlyingDebt'] / 100)
    environment.notional.withdraw(3, maxPrimeCash, True, {"from": accounts[0]})

    with brownie.reverts("Over Debt Cap"):
        environment.notional.withdraw(3, 1e8, True, {"from": accounts[0]})

    proxy = Contract.from_abi('pUSDC', environment.notional.pCashAddress(3), PrimeCashProxy.abi)
    erc20 = Contract.from_abi("erc20", proxy.asset(), MockERC20.abi)
    depositAmount = 1e6
    assets = proxy.previewDeposit(depositAmount)

    erc20.approve(proxy, 2 ** 255 - 1, {"from": accounts[1]})
    with brownie.reverts("Over Supply Cap"):
        proxy.mint(assets, accounts[1], {"from": accounts[1]})

    with brownie.reverts("Over Supply Cap"):
        proxy.deposit(depositAmount, accounts[1], {"from": accounts[1]})

@given(
    currencyId=strategy("uint", min_value=1, max_value=3),
    useSender=strategy("bool"),
    useReceiver=strategy("bool")
)
def test_redeem(environment, accounts, currencyId, useSender, useReceiver):
    proxy = Contract.from_abi('pETH', environment.notional.pCashAddress(currencyId), PrimeCashProxy.abi)
    erc20 = Contract.from_abi("erc20", proxy.asset(), MockERC20.abi)
    if currencyId != 1:
        environment.notional.depositUnderlyingToken(
            accounts[0], currencyId, 10 ** erc20.decimals() * 10, {"from": accounts[0]}
        )
    redeemAmount = 50e8

    receiver = accounts[1] if useReceiver else accounts[0]
    sender = accounts[2] if useSender else accounts[0]
    withdrawAmount = proxy.previewRedeem(redeemAmount)

    if useSender:
        with brownie.reverts("Insufficient allowance"):
            proxy.redeem(redeemAmount, receiver, accounts[0], {"from": sender})
        proxy.approve(sender, redeemAmount, {"from": accounts[0]})

    pCashBalanceBefore = proxy.balanceOf(accounts[0])
    senderApprovalBefore = proxy.allowance(accounts[0], sender)
    balanceBefore = erc20.balanceOf(receiver)

    proxy.redeem(redeemAmount, receiver, accounts[0], {"from": sender})

    senderApprovalAfter = proxy.allowance(accounts[0], sender)
    pCashBalanceAfter = proxy.balanceOf(accounts[0])
    balanceAfter = erc20.balanceOf(receiver)

    (cashBalance, _, _) = environment.notional.getAccountBalance(currencyId, accounts[0])
    assert cashBalance == proxy.balanceOf(accounts[0])

    assert pytest.approx(balanceAfter - balanceBefore, rel=1e-6, abs=100) == withdrawAmount
    assert pCashBalanceBefore - pCashBalanceAfter == redeemAmount
    if useSender:
        assert senderApprovalBefore - senderApprovalAfter == redeemAmount

    check_system_invariants(environment, accounts)

@given(
    currencyId=strategy("uint", min_value=1, max_value=3),
    useSender=strategy("bool"),
    useReceiver=strategy("bool")
)
def test_withdraw(environment, accounts, currencyId, useSender, useReceiver):
    proxy = Contract.from_abi('pETH', environment.notional.pCashAddress(currencyId), PrimeCashProxy.abi)
    erc20 = Contract.from_abi("erc20", proxy.asset(), MockERC20.abi)
    if currencyId != 1:
        environment.notional.depositUnderlyingToken(
            accounts[0], currencyId, 10 ** erc20.decimals() * 10, {"from": accounts[0]}
        )
    redeemAmount = 50e8

    receiver = accounts[1] if useReceiver else accounts[0]
    sender = accounts[2] if useSender else accounts[0]
    withdrawAmount = proxy.previewRedeem(redeemAmount)

    if useSender:
        with brownie.reverts("Insufficient allowance"):
            proxy.withdraw(withdrawAmount, receiver, accounts[0], {"from": sender})
        proxy.approve(sender, proxy.previewWithdraw(withdrawAmount), {"from": accounts[0]})

    pCashBalanceBefore = proxy.balanceOf(accounts[0])
    senderApprovalBefore = proxy.allowance(accounts[0], sender)
    balanceBefore = erc20.balanceOf(receiver)

    proxy.withdraw(withdrawAmount, receiver, accounts[0], {"from": sender})

    senderApprovalAfter = proxy.allowance(accounts[0], sender)
    pCashBalanceAfter = proxy.balanceOf(accounts[0])
    balanceAfter = erc20.balanceOf(receiver)

    (cashBalance, _, _) = environment.notional.getAccountBalance(currencyId, accounts[0])
    assert cashBalance == proxy.balanceOf(accounts[0])

    assert balanceAfter - balanceBefore == withdrawAmount
    if currencyId == 3:
        assert balanceAfter - balanceBefore == withdrawAmount
        # Redeeming USDC balances results in larger redemption values
        assert pytest.approx(pCashBalanceBefore - pCashBalanceAfter, rel=1e-6) == redeemAmount
        if useSender:
            assert pytest.approx(senderApprovalBefore - senderApprovalAfter, rel=1e-6) == redeemAmount
    else:
        assert pytest.approx(pCashBalanceBefore - pCashBalanceAfter, abs=100) == redeemAmount
        if useSender:
            assert pytest.approx(senderApprovalBefore - senderApprovalAfter, abs=100) == redeemAmount


    check_system_invariants(environment, accounts)

def test_cannot_withdraw_to_negative_balance(environment, accounts):
    proxy = Contract.from_abi('pDAI', environment.notional.pCashAddress(2), PrimeCashProxy.abi)
    environment.notional.depositUnderlyingToken(
        accounts[0], 2, 10e18, {"from": accounts[0]}
    )

    with brownie.reverts("Insufficient Balance"):
        proxy.redeem(proxy.balanceOf(accounts[0]) + 1,
                     accounts[0], accounts[0], {"from": accounts[0]})

    with brownie.reverts("Insufficient Balance"):
        proxy.withdraw(proxy.convertToAssets(proxy.balanceOf(accounts[0]) + 1e8), 
                       accounts[0], accounts[0], {"from": accounts[0]})


def test_cannot_withdraw_below_fc(environment, accounts):
    proxy = Contract.from_abi('pETH', environment.notional.pCashAddress(1), PrimeCashProxy.abi)
    erc20 = Contract.from_abi("erc20", proxy.asset(), MockERC20.abi)
    environment.notional.depositUnderlyingToken(
        accounts[1], 1, 10 ** erc20.decimals() * 10, {"from": accounts[1], "value": 10e18}
    )

    # Borrow USDC
    environment.notional.enablePrimeBorrow(True, {"from": accounts[1]})
    environment.notional.withdraw(3, 1_000e8, True, {"from": accounts[1]})

    with brownie.reverts("Insufficient free collateral"):
        proxy.redeem(proxy.balanceOf(accounts[1]), accounts[1], accounts[1], {"from": accounts[1]})

    with brownie.reverts("Insufficient free collateral"):
        proxy.withdraw(9.9e18, accounts[1], accounts[1], {"from": accounts[1]})


def test_cannot_call_withdraw_via_proxy(environment, accounts):
    with brownie.reverts():
        environment.notional.withdrawViaProxy(
            1,
            accounts[0],
            accounts[0],
            accounts[0],
            100e8,
            {"from": accounts[0]}
        )
