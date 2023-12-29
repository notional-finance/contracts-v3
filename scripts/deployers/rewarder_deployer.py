from brownie import SecondaryRewarder, accounts
from scripts.inspect import get_addresses

rewarderConfig = {
    'currencyId': 8,
    'rewardToken': '0x912CE59144191C1204E64559FE8253a0e49E6548', # ARB
    'initialEmissionRate': 52e8, # Approx 1e8 ARB per week
    'endTime': 1704441600, # Jan 5 00:00:00
}

def main():
    (_, notional, *_) =get_addresses()
    deployer = accounts.load('DEPLOYER')

    rewarder = SecondaryRewarder.deploy(
        notional.address,
        rewarderConfig['currencyId'],
        rewarderConfig['rewardToken'],
        rewarderConfig['initialEmissionRate'],
        rewarderConfig['endTime'],
        {"from": deployer}
    )

    notional.setSecondaryIncentiveRewarder(
        rewarderConfig['currencyId'], rewarder,
        {"from": notional.owner()}
    )