import json
from brownie import (
    ZERO_ADDRESS,
    Contract, accounts,
    UnderlyingHoldingsOracle,
    EmptyProxy,
    nProxy,
    UpgradeableBeacon,
    nTokenERC20Proxy,
    PrimeCashProxy,
    PrimeDebtProxy,
    interface
)
from brownie.network import Chain
from scripts.arbitrum.arb_config import ListedOrder, ListedTokens
from scripts.common import TokenType
from scripts.deployers.oracle_deployer import deploy_chainlink_oracle
from scripts.deployment import deployNotionalContracts
from tests.helpers import get_balance_action

chain = Chain()

OWNER = "0xbf778Fc19d0B55575711B6339A3680d07352B221"
DEPLOYER = "0x8B64fA5Fd129df9c755eB82dB1e16D6D0Bdf5Bc3"
BEACON_DEPLOYER = "0x0D251Bd6c14e02d34f68BFCB02c54cBa3D108122"

WHALES = {
    # GMX Vault
    'ETH': "0x489ee077994b6658eafa855c308275ead8097c4a",
    'DAI': "0x489ee077994b6658eafa855c308275ead8097c4a",
    'USDC': "0x489ee077994b6658eafa855c308275ead8097c4a",
    'WBTC': "0x489ee077994b6658eafa855c308275ead8097c4a",
    'wstETH': "0xba12222222228d8ba445958a75a0704d566bf2c8",
    'FRAX':  "0x489ee077994b6658eafa855c308275ead8097c4a"
}

def deploy_note_proxy(deployer, emptyProxy):
    assert deployer.address == DEPLOYER
    assert deployer.nonce == 1
    # Must be nonce == 1
    # https://etherscan.io/tx/0xcd23bcecfef5de7afcc76d32350055de906d3394fcf1d35f3490a7c62926cb64
    return nProxy.deploy(emptyProxy, bytes(), {"from": deployer})

def deploy_notional_proxy(deployer, router, calldata):
    assert deployer.address == DEPLOYER
    assert deployer.nonce == 28
    # Must be nonce = 28
    # https://etherscan.io/tx/0xd1334bf8efcbc152b3e8de40887f534171a9993082e8b4d6187bd6271e7ac0b9
    notional = nProxy.deploy(router, calldata, {"from": deployer})
    assert notional.address == "0x1344A36A1B56144C3Bc62E7757377D288fDE0369"
    return notional

def deploy_beacons(deployer, emptyProxy):
    assert deployer.address == BEACON_DEPLOYER
    assert deployer.nonce == 0

    nTokenBeacon = UpgradeableBeacon.deploy(emptyProxy, {"from": deployer})
    assert nTokenBeacon.address == "0xc4FD259b816d081C8bdd22D6bbd3495DB1573DB7"
    pCashBeacon = UpgradeableBeacon.deploy(emptyProxy, {"from": deployer})
    assert pCashBeacon.address == "0x1F681977aF5392d9Ca5572FB394BC4D12939A6A9"
    pDebtBeacon = UpgradeableBeacon.deploy(emptyProxy, {"from": deployer})
    assert pDebtBeacon.address == "0xDF08039c0af34E34660aC7c2705C0Da953247640"
    wfCashBeacon = UpgradeableBeacon.deploy(emptyProxy, {"from": deployer})
    assert wfCashBeacon.address == "0xEBe1BF1653d55d31F6ED38B1A4CcFE2A92338f66"

    return ( nTokenBeacon, pCashBeacon, pDebtBeacon, wfCashBeacon )

def list_currency(symbol, notional, deployer, fundingAccount, config):
    pCashOracle = _deploy_pcash_oracle(symbol, notional, deployer, config)
    ethOracle = deploy_chainlink_oracle(symbol, deployer, config)
    _list_currency(symbol, notional, deployer, pCashOracle, ethOracle, fundingAccount, config)

def _deploy_pcash_oracle(symbol, notional, deployer, config):
    token = config[symbol]
    return UnderlyingHoldingsOracle.deploy(notional.address, token['address'], {"from": deployer})

def _to_interest_rate_curve(params):
    return (
        params["kinkUtilization1"],
        params["kinkUtilization2"],
        params["kinkRate1"],
        params["kinkRate2"],
        params["maxRate25BPS"],
        params["minFeeRate5BPS"],
        params["maxFeeRate25BPS"],
        params["feeRatePercent"],
    )

def _list_currency(symbol, notional, deployer, pCashOracle, ethOracle, fundingAccount, config):
    token = config[symbol]
    # Minimum underlying held is 0.05e8 in internal decimals
    if symbol == 'ETH':
        fundingAccount.transfer(notional, 0.05e18)
    else:
        erc20 = Contract.from_abi("token", token['address'], interface.IERC20.abi)
        decimals = erc20.decimals()
        # Donate the initial balance
        erc20.transfer(notional, 0.05 * 10 ** decimals, {"from": fundingAccount})

    txn = notional.listCurrency(
        (
            token['address'],
            False,
            TokenType["UnderlyingToken"] if symbol != "ETH" else TokenType["Ether"],
            token['decimals'],
            0,
        ),
        (
            ethOracle,
            18,
            False,
            token["buffer"],
            token["haircut"],
            token["liquidationDiscount"],
        ),
        _to_interest_rate_curve(token['primeCashCurve']),
        pCashOracle,
        True,  # allowDebt
        token['primeRateOracleTimeWindow5Min'],
        token['name'],
        symbol,
        {"from": deployer}
    )
    currencyId = txn.events["ListCurrency"]["newCurrencyId"]

    notional.setMaxUnderlyingSupply(
        currencyId,
        token['maxUnderlyingSupply'],
        token['primeCashCurve']['kinkUtilization2'],
        {"from": deployer}
    )

    if "maxMarketIndex" in token:
        notional.enableCashGroup(
            currencyId,
            (
                token["maxMarketIndex"],
                token["rateOracleTimeWindow"],
                token["maxDiscountFactor"],
                token["reserveFeeShare"],
                token["debtBuffer"],
                token["fCashHaircut"],
                token["minOracleRate"],
                token["liquidationfCashDiscount"],
                token["liquidationDebtBuffer"],
                token["maxOracleRate"]
            ),
            token['name'],
            symbol,
            {"from": deployer}
        )

        notional.updateInterestRateCurve(
            currencyId,
            [1, 2],
            [_to_interest_rate_curve(c) for c in token['fCashCurves']],
            {"from": deployer}
        )

        notional.updateDepositParameters(currencyId, token['depositShare'], token['leverageThreshold'], {"from": deployer})

        notional.updateInitializationParameters(currencyId, [0, 0], token['proportion'], {"from": deployer})

        notional.updateTokenCollateralParameters(
            currencyId,
            token["residualPurchaseIncentive"],
            token["pvHaircutPercentage"],
            token["residualPurchaseTimeBufferHours"],
            token["cashWithholdingBuffer10BPS"],
            token["liquidationHaircutPercentage"],
            token["maxMintDeviation5BPS"],
            {"from": deployer}
        )

def initialize_markets(notional, fundingAccount, order, config):
    actions = []
    initMarkets = []
    for symbol in order:
        token = config[symbol]
        currencyId = token["currencyId"]
        if symbol == 'ETH':
            actions.append(
                get_balance_action(currencyId, "DepositUnderlyingAndMintNToken", depositActionAmount=0.5e18)
            )
            initMarkets.append(currencyId)
        elif "fCashCurves" in token:
            erc20 = Contract.from_abi("token", token['address'], interface.IERC20.abi)
            # Donate the initial balance
            balance = erc20.balanceOf(fundingAccount)
            erc20.approve(notional.address, 2 ** 256 - 1, {"from": fundingAccount})
            actions.append(
                get_balance_action(currencyId, "DepositUnderlyingAndMintNToken", depositActionAmount=balance)
            )
            initMarkets.append(currencyId)

    notional.batchBalanceAction(fundingAccount, actions, {"from": fundingAccount, "value": 0.5e18})
    calldata = [
        (notional.address, notional.initializeMarkets.encode_input(i, True))
        for i in initMarkets
    ]
    multicall_abi = json.load(open("./abi/Multicall3.json"))
    multicall = Contract.from_abi("multicall", "0xcA11bde05977b3631167028862bE2a173976CA11", multicall_abi)
    multicall.aggregate(calldata, {"from": fundingAccount})


BeaconType = {
    "NTOKEN": 0,
    "PCASH": 1,
    "PDEBT": 2,
    "WFCASH": 3,
}

def set_beacons(notional, beaconDeployer, nTokenBeacon, pCashBeacon, pDebtBeacon, deployer):
    nTokenBeacon.transferOwnership(notional.address, {"from": beaconDeployer})
    pCashBeacon.transferOwnership(notional.address, {"from": beaconDeployer})
    pDebtBeacon.transferOwnership(notional.address, {"from": beaconDeployer})

    nTokenImpl = nTokenERC20Proxy.deploy(notional.address, {"from": deployer})
    pCashImpl = PrimeCashProxy.deploy(notional.address, {"from": deployer})
    pDebtImpl = PrimeDebtProxy.deploy(notional.address, {"from": deployer})

    notional.upgradeBeacon(BeaconType["NTOKEN"], nTokenImpl, {"from": deployer})
    notional.upgradeBeacon(BeaconType["PCASH"], pCashImpl, {"from": deployer})
    notional.upgradeBeacon(BeaconType["PDEBT"], pDebtImpl, {"from": deployer})


def main():
    if chain.id != 42161:
        raise Exception("Incorrect Chain Id")

    deployer = accounts.at(DEPLOYER, force=True)
    beaconDeployer = accounts.at(BEACON_DEPLOYER, force=True)
    fundingAccount = accounts.at("0x7d7935EDd4b6cDB5f34B0E1cCEAF85a3C4A11254", force=True)
    owner = accounts.at(OWNER, force=True)

    impl = EmptyProxy.deploy(owner, {"from": deployer})
    deploy_note_proxy(deployer, impl)
    (nTokenBeacon, pCashBeacon, pDebtBeacon) = deploy_beacons(beaconDeployer, impl)

    (router, pauseRouter, contracts) = deployNotionalContracts(deployer, Comptroller=ZERO_ADDRESS)
    deployer.transfer(deployer, 0)
    deployer.transfer(deployer, 0)
    deployer.transfer(deployer, 0)
    # Deployer is set to the owner here for initialization
    calldata = router.initialize.encode_input(deployer, pauseRouter, owner)
    notional = deploy_notional_proxy(deployer, router, calldata)

    proxy = Contract.from_abi("notional", notional.address, EmptyProxy.abi, deployer)
    # proxy.upgradeToAndCall(router, calldata, {"from": deployer})
    assert notional.getImplementation() == router.address

    try:
        proxy.upgradeToAndCall.call(router, calldata, {"from": deployer})
        assert False
    except:
        # Cannot Re-Initialize
        assert True

    notional = Contract.from_abi("notional", notional.address, interface.NotionalProxy.abi)
    set_beacons(notional, beaconDeployer, nTokenBeacon, pCashBeacon, pDebtBeacon, deployer)

    for c in ListedOrder:
        list_currency(c, notional, deployer, fundingAccount, ListedTokens)

    initialize_markets(notional, fundingAccount)

    for (i, symbol) in enumerate(ListedOrder):
        try:
            token = ListedTokens[symbol]
            whale = WHALES[symbol]
            # Donate the initial balance
            if symbol != "ETH":
                erc20 = Contract.from_abi("token", token['address'], interface.IERC20.abi)
                balance = erc20.balanceOf(whale)
                erc20.approve(notional.address, 2 ** 256 - 1, {"from": whale})
                msgValue = 0
            else:
                balance = 10e18
                msgValue = 10e18

            notional.depositUnderlyingToken(WHALES[symbol], i + 1, balance, {"from": whale, "value": msgValue})
        except Exception as err:
            assert err.revert_msg == "Over Supply Cap"

    # Deployer needs to transfer ownership to the owner
    notional.transferOwnership(owner, False, {"from": deployer})
    assert notional.owner() == deployer

    for (i, symbol) in enumerate(ListedOrder):
        rates = [ m[5] / 1e9 for m in notional.getActiveMarkets(i + 1) ]
        print("Market Rates for {}: {}".format(symbol, rates))
        