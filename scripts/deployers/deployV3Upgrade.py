#!/bin/python
import json
from brownie import ZERO_ADDRESS, Contract, accounts, CompoundV2HoldingsOracle, EmptyProxy, UpgradeableBeacon, nTokenERC20Proxy, PrimeCashProxy, PrimeDebtProxy, interface, network, MigrationSettings, MigratePrimeCash
from brownie.network import Chain
from scripts.deployment import deployNotionalContracts

chain = Chain()

OWNER = "0xf862895976F693907f0AF8421Fe9264e559c2f6b"
DEPLOYER = "0x8B64fA5Fd129df9c755eB82dB1e16D6D0Bdf5Bc3"
BEACON_DEPLOYER = "0x0D251Bd6c14e02d34f68BFCB02c54cBa3D108122"

BeaconType = {
    "NTOKEN": 0,
    "PCASH": 1,
    "PDEBT": 2,
    "WFCASH": 3,
}

# This is on Goerli
LISTED_TOKENS = [
    {
        "symbol": "ETH",
        "address": "0x0000000000000000000000000000000000000000",
        "cToken": "0x97B44D189719Aa669f878cf0e558f86831D98E52",
        "cTokenRateAdapter": "0x97B44D189719Aa669f878cf0e558f86831D98E52"
    },
    {
        "symbol": "DAI",
        "address": "0x84e90bddff9a0e124f1ab7f4d1d33a7c748c1a16",
        "cToken": "0xeBE9243F7251922Bc0e5d33Dd329752158d10FaA",
        "cTokenRateAdapter": "0xeBE9243F7251922Bc0e5d33Dd329752158d10FaA"
    },
    {
        "symbol": "USDC",
        "address": "0x31dd61ac1b7a0bc88f7a58389c0660833a66c35c",
        "cToken": "0x3eFeA902182ce4B732A8ff8DAd106163fe7c023f",
        "cTokenRateAdapter": "0x3eFeA902182ce4B732A8ff8DAd106163fe7c023f"
    },
    {
        "symbol": "WBTC",
        "address": "0xfa8589db27c6369a6a4fdd857f783eddf857f2bc",
        "cToken": "0xEB3d46833144563553B2cB7057D1d89E291f5d68",
        "cTokenRateAdapter": "0xEB3d46833144563553B2cB7057D1d89E291f5d68"
    }
]

def deploy_beacons(deployer, emptyProxy, notional):
    assert deployer.address == BEACON_DEPLOYER
    assert deployer.nonce == 0

    nTokenBeacon = UpgradeableBeacon.deploy(emptyProxy, {"from": deployer})
    assert nTokenBeacon.address == "0xc4FD259b816d081C8bdd22D6bbd3495DB1573DB7"
    pCashBeacon = UpgradeableBeacon.deploy(emptyProxy, {"from": deployer})
    assert pCashBeacon.address == "0x1F681977aF5392d9Ca5572FB394BC4D12939A6A9"
    pDebtBeacon = UpgradeableBeacon.deploy(emptyProxy, {"from": deployer})
    assert pDebtBeacon.address == "0xDF08039c0af34E34660aC7c2705C0Da953247640"

    nTokenImpl = nTokenERC20Proxy.deploy(notional.address, {"from": deployer})
    pCashImpl = PrimeCashProxy.deploy(notional.address, {"from": deployer})
    pDebtImpl = PrimeDebtProxy.deploy(notional.address, {"from": deployer})

    nTokenBeacon.upgradeTo(nTokenImpl.address, {"from": deployer})
    pCashBeacon.upgradeTo(pCashImpl.address, {"from": deployer})
    pDebtBeacon.upgradeTo(pDebtImpl.address, {"from": deployer})

    nTokenBeacon.transferOwnership(notional.address, {"from": deployer})
    pCashBeacon.transferOwnership(notional.address, {"from": deployer})
    pDebtBeacon.transferOwnership(notional.address, {"from": deployer})

    # Nonce 103 and 104
    # https://etherscan.io/tx/0x947d60c781254637c5b9e774d8910a1187a31de606b3d3a515b6981662536fd2I
    # https://etherscan.io/tx/0x54c63544f562fd997d81fec94bc2189977b996e2ada8e3839e635aea513a6291
    # wfCashBeacon = UpgradeableBeacon.deploy(impl, {"from": deployer})

    return ( nTokenBeacon, pCashBeacon, pDebtBeacon )


def main():
    networkName = network.show_active()
    if networkName == "mainnet-fork" or networkName == "mainnet-current":
        networkName = "mainnet"
    if networkName == "goerli-fork":
        networkName = "goerli"
    output_file = "v2.{}.json".format(networkName)
    addresses = None
    with open(output_file, "r") as f:
        addresses = json.load(f)

    deployer = accounts.at(DEPLOYER, force=True)
    owner = accounts.at(OWNER, force=True)
    beaconDeployer = accounts.at(BEACON_DEPLOYER, force=True)

    notional = Contract.from_abi("Notional", addresses["notional"], abi=interface.NotionalProxy.abi)

    impl = EmptyProxy.deploy(owner, {"from": deployer})
    (nTokenBeacon, pCashBeacon, pDebtBeacon) = deploy_beacons(beaconDeployer, impl, notional)
    (router, pauseRouter, contracts) = deployNotionalContracts(deployer, Comptroller=ZERO_ADDRESS)

    print("New Router", router.address)
    print("New Pause Router", pauseRouter)

    for token in LISTED_TOKENS:
        oracle = CompoundV2HoldingsOracle.deploy([
            notional.address,
            token['address'],
            token['cToken'],
            token['cTokenRateAdapter']
        ], {"from": deployer})
        print("Token Oracle {}: {}".format(token['symbol'], oracle.address))

    # Migration Settings
    settings = MigrationSettings.deploy(notional.address, owner, {"from": deployer})
    print("Settings", settings.address)

    # Migrate Prime Cash
    migrate = MigratePrimeCash.deploy(
        settings.address,
        router,
        pauseRouter,
        owner,
        {"from": deployer}
    )
    print("Migrate", migrate.address)

