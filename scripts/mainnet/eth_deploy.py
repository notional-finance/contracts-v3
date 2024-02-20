from brownie import ZERO_ADDRESS, Contract, accounts,  EmptyProxy, nProxy, interface, history
from brownie.network import Chain
from scripts.arbitrum.arb_deploy import deploy_beacons, initialize_markets, list_currency, set_beacons
from scripts.deployment import deployNotionalContracts
from scripts.mainnet.eth_config import ListedOrder, ListedTokens

chain = Chain()

OWNER = "0x22341fB5D92D3d801144aA5A925F401A91418A05"
DEPLOYER = "0x8B64fA5Fd129df9c755eB82dB1e16D6D0Bdf5Bc3"
BEACON_DEPLOYER = "0x0D251Bd6c14e02d34f68BFCB02c54cBa3D108122"

# Matic Bridge
WHALES = {
    'DAI': "0x40ec5B33f54e0E8A33A975908C5BA1c14e5BbbDf",
    'USDC': "0x40ec5B33f54e0E8A33A975908C5BA1c14e5BbbDf",
    'WBTC': "0x40ec5B33f54e0E8A33A975908C5BA1c14e5BbbDf",
    'wstETH': "0x40ec5B33f54e0E8A33A975908C5BA1c14e5BbbDf",
    'FRAX': "0x40ec5B33f54e0E8A33A975908C5BA1c14e5BbbDf",
    'rETH': "0x40ec5B33f54e0E8A33A975908C5BA1c14e5BbbDf",
    'USDT': "0x40ec5B33f54e0E8A33A975908C5BA1c14e5BbbDf",
    # Arb Gateway
    'cbETH': "0xa3A7B6F88361F48403514059F1F16C8E78d60EeC",
    # Gnosis Bridge
    'sDAI': "0x4aa42145Aa6Ebf72e164C9bBC74fbD3788045016"
}

def main():
    deployer = accounts.at(DEPLOYER, force=True)
    beaconDeployer = accounts.at(BEACON_DEPLOYER, force=True)
    fundingAccount = accounts.at("0x7d7935EDd4b6cDB5f34B0E1cCEAF85a3C4A11254", force=True)
    owner = accounts.at(OWNER, force=True)

    impl = EmptyProxy.at("0x90c3c405716B8fF965dc905C91eee82A0b41A4fF")
    (nTokenBeacon, pCashBeacon, pDebtBeacon) = deploy_beacons(beaconDeployer, impl)

    (router, pauseRouter, contracts) = deployNotionalContracts(deployer)

    calldata = router.initialize.encode_input(deployer, pauseRouter, owner)
    notional = nProxy.deploy(router, calldata, {"from": deployer})

    proxy = Contract.from_abi("notional", notional.address, EmptyProxy.abi, deployer)
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
        token = ListedTokens[c]
        if c != "ETH":
            erc20 = Contract.from_abi("token", token['address'], interface.IERC20.abi)
            erc20.transfer(fundingAccount, 10 ** erc20.decimals(), {"from": WHALES[c]})
        list_currency(c, notional, deployer, fundingAccount, ListedTokens)

    initialize_markets(notional, fundingAccount, ListedOrder, ListedTokens)

    # Deployer needs to transfer ownership to the owner
    notional.transferOwnership(owner, False, {"from": deployer})
    assert notional.owner() == deployer

    for (i, symbol) in enumerate(ListedOrder):
        rates = [ m[5] / 1e9 for m in notional.getActiveMarkets(i + 1) ]
        print("Market Rates for {}: {}".format(symbol, rates))
    
    print("Gas Costs")
    gas_used("Beacon Deployer", beaconDeployer)
    gas_used("Contract Deployer", deployer)
    gas_used("Owner", owner)
    gas_used("Funding", fundingAccount)

def gas_used(label, account):
    print("{}: {:,} gas, {:,.4f} ETH @ 40 gwei, {} txns".format(
        label,
        sum([ tx.gas_used for tx in history.from_sender(account) ]),
        sum([ tx.gas_used for tx in history.from_sender(account) ]) * 40e9 / 1e18,
        len(history.from_sender(account))
    ))
