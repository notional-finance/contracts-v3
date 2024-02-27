from brownie import ZERO_ADDRESS, Contract, accounts,  EmptyProxy, nProxy, interface, history, Router, network, UpgradeableBeacon, MockERC20
from brownie.network import Chain
from scripts.arbitrum.arb_deploy import deploy_beacons, initialize_markets, list_currency, set_beacons
from scripts.deploy_v3 import deployNotional
from scripts.deployment import deployNotionalContracts
from scripts.initializers.list_currency import check_trading_module_oracle
from scripts.mainnet.eth_config import ListedOrder, ListedTokens

chain = Chain()

OWNER = "0x22341fB5D92D3d801144aA5A925F401A91418A05"
PAUSE_GUARDIAN = "0xD9D5a9dc6a952b7aD6B05a983b399537B7c0Ee88"
NOTIONAL_INC = "0x02479BFC7Dce53A02e26fE7baea45a0852CB0909"
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
    networkName = network.show_active()
    if networkName in ["mainnet-fork", "mainnet-current"]:
        networkName = "mainnet"
        isFork = True
        deployer = accounts.at(DEPLOYER, force=True)
        beaconDeployer = accounts.at(BEACON_DEPLOYER, force=True)
    elif networkName == "mainnet":
        isFork = False
        deployer = accounts.load("MAINNET_DEPLOYER")
        beaconDeployer = accounts.load("BEACON_DEPLOYER")

    fundingAccount = deployer

    # This implementation doesn't actually matter for the beacon
    # impl = EmptyProxy.at("0x90c3c405716B8fF965dc905C91eee82A0b41A4fF")
    # (nTokenBeacon, pCashBeacon, pDebtBeacon, wfCashBeacon) = deploy_beacons(beaconDeployer, impl)

    # n = deployNotional(deployer, "mainnet", False, True)
    # # (router, pauseRouter, contracts) = deployNotionalContracts(deployer)
    # router = Router.at(n.routers['Router'])
    # pauseRouter = n.routers['PauseRouter']

    # calldata = router.initialize.encode_input(deployer, pauseRouter, PAUSE_GUARDIAN)
    # print("Beacon Deployer Nonce", beaconDeployer.nonce)
    # notional = nProxy.deploy(router, calldata, {"from": beaconDeployer})
    # assert notional.address == "0x6e7058c91F85E0F6db4fc9da2CA41241f5e4263f"

    # proxy = Contract.from_abi("notional", notional.address, EmptyProxy.abi, deployer)
    # assert notional.getImplementation() == router.address

    # try:
    #     proxy.upgradeToAndCall.call(router, calldata, {"from": deployer})
    #     assert False
    # except:
    #     # Cannot Re-Initialize
    #     assert True

    notional = Contract.from_abi("notional", "0x6e7058c91F85E0F6db4fc9da2CA41241f5e4263f", interface.NotionalProxy.abi)
    # set_beacons(notional, beaconDeployer, nTokenBeacon, pCashBeacon, pDebtBeacon, deployer)

    id = 1
    for c in ListedOrder:
        # token = ListedTokens[c]
        # if c != "ETH":
        #     erc20 = Contract.from_abi("token", token['address'], interface.IERC20.abi)
        #     erc20.transfer(fundingAccount, 10 ** erc20.decimals(), {"from": WHALES[c]})
        list_currency(c, notional, deployer, fundingAccount, ListedTokens)
        check_trading_module_oracle(c, ListedTokens, isFork)
        try:
            nToken = MockERC20.at(notional.nTokenAddress(id))
            print("nToken: ", nToken.symbol(), nToken.name())
        except:
            pass
        pCash = MockERC20.at(notional.pCashAddress(id))
        print("pCash: ", pCash.symbol(), pCash.name())
        pDebt = MockERC20.at(notional.pDebtAddress(id))
        print("pCash: ", pDebt.symbol(), pDebt.name())
        id += 1

    initialize_markets(notional, fundingAccount, ListedOrder, ListedTokens)

    # Deployer needs to transfer ownership to the owner
    # notional.transferOwnership(OWNER, False, {"from": deployer})
    # assert notional.owner() == deployer

    for (i, symbol) in enumerate(ListedOrder):
        rates = [ m[5] / 1e9 for m in notional.getActiveMarkets(i + 1) ]
        print("Market Rates for {}: {}".format(symbol, rates))
    
    print("Gas Costs")
    # gas_used("Beacon Deployer", beaconDeployer)
    gas_used("Contract Deployer", deployer)
    # gas_used("Owner", owner)
    # gas_used("Funding", fundingAccount)

def gas_used(label, account):
    print("{}: {:,} gas, {:,.4f} ETH @ 40 gwei, {} txns".format(
        label,
        sum([ tx.gas_used for tx in history.from_sender(account) ]),
        sum([ tx.gas_used for tx in history.from_sender(account) ]) * 40e9 / 1e18,
        len(history.from_sender(account))
    ))
