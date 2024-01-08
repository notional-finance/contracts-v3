from brownie import SecondaryRewarder, accounts, MockERC20
from scripts.inspect import get_addresses

END_TIME = 1705708800 # Jan 20
ARB = '0x912CE59144191C1204E64559FE8253a0e49E6548'
REWARDERS = {
    "ETH": "0x3987F211d4BA25B6FF163B56051651bF6c6c5e54",
    "DAI": "0xE5b58DE62b71477aE4e10074fee48232DD7A2350",
    "USDC": "0xFc24ACF5BD2aFEe3efBd589F87B6610C9D162645",
    "WBTC": "0x8BC5600582c6c17194e4478C311d3133cf9361D2",
    "wstETH": "0xd2Da21d240F093A38A143426D3cd62326FC496cc",
    "FRAX": "0xA8cA4FA84933106a92D4fec68C8B5A057703e862",
    "rETH": "0xda99cd202bCac9f9c945fF2954e08EAec63B067d",
    "USDT": "0xe670942CE88d0ac8E655d30E5EF0229e969de26C",
    "cbETH": "0x9Bfbd9DF9E5f0bA9B43843bf89B590e41Ac01174"
}

def main():
    (_, notional, *_) = get_addresses()

    # eth = SecondaryRewarder.deploy(
    #     notional.address, 1, ARB, 0, END_TIME, {"from": deployer}
    # )
    # assert MockERC20.at(eth.NTOKEN_ADDRESS()).symbol() == 'nETH'
    # assert eth.emissionRatePerYear() == 0

    SecondaryRewarder.at(REWARDERS['ETH']).setIncentiveEmissionRate(
        10_909e8, END_TIME, {"from": notional.owner()}
    )
    SecondaryRewarder.at(REWARDERS['DAI']).setIncentiveEmissionRate(
        4_545e8, END_TIME, {"from": notional.owner()}
    )
    SecondaryRewarder.at(REWARDERS['USDC']).setIncentiveEmissionRate(
        10_909e8, END_TIME, {"from": notional.owner()}
    )
    SecondaryRewarder.at(REWARDERS['WBTC']).setIncentiveEmissionRate(
        909e8, END_TIME, {"from": notional.owner()}
    )
    SecondaryRewarder.at(REWARDERS['wstETH']).setIncentiveEmissionRate(
        4_545e8, END_TIME, {"from": notional.owner()}
    )
    SecondaryRewarder.at(REWARDERS['FRAX']).setIncentiveEmissionRate(
        4_545e8, END_TIME, {"from": notional.owner()}
    )
    SecondaryRewarder.at(REWARDERS['rETH']).setIncentiveEmissionRate(
        4_545e8, END_TIME, {"from": notional.owner()}
    )
    SecondaryRewarder.at(REWARDERS['USDT']).setIncentiveEmissionRate(
        4_545e8, END_TIME, {"from": notional.owner()}
    )

    notional.setSecondaryIncentiveRewarder(1, REWARDERS['ETH'], {"from": notional.owner()})
    notional.setSecondaryIncentiveRewarder(2, REWARDERS['DAI'], {"from": notional.owner()})
    notional.setSecondaryIncentiveRewarder(3, REWARDERS['USDC'], {"from": notional.owner()})
    notional.setSecondaryIncentiveRewarder(4, REWARDERS['WBTC'], {"from": notional.owner()})
    notional.setSecondaryIncentiveRewarder(5, REWARDERS['wstETH'], {"from": notional.owner()})
    notional.setSecondaryIncentiveRewarder(6, REWARDERS['FRAX'], {"from": notional.owner()})
    notional.setSecondaryIncentiveRewarder(7, REWARDERS['rETH'], {"from": notional.owner()})
    # USDT is already set
    # notional.setSecondaryIncentive(9, REWARDERS['cbETH'])