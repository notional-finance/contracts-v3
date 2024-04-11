from brownie import ZERO_ADDRESS, accounts
from scripts.deployers.oracle_deployer import deploy_chainlink_usd_oracle
# from scripts.mainnet.eth_config import ChainlinkOracles
from scripts.arbitrum.arb_config import ChainlinkOracles

DEPLOYER = "0x8B64fA5Fd129df9c755eB82dB1e16D6D0Bdf5Bc3"

# Mainnet: 0xCa140AE5a361b7434A729dCadA0ea60a50e249dd
# Arbitrum: 0x58784379C844a00d4f572917D43f991c971F96ca
ezETH_USD = {
    'oracleType': 'ChainlinkAdapter',
    'baseOracle': ChainlinkOracles['ezETH/ETH'],
    'quoteOracle': ChainlinkOracles['ETH/USD'],
    'invertBase': False,
    'invertQuote': True,
    'sequencerUptimeOracle': ZERO_ADDRESS
}

# Mainnet: 0xdDb6F90fFb4d3257dd666b69178e5B3c5Bf41136
# Arbitrum: 0x9414609789C179e1295E9a0559d629bF832b3c04
weETH_USD = {
    'oracleType': 'ChainlinkAdapter',
    'baseOracle': ChainlinkOracles['weETH/ETH'],
    'quoteOracle': ChainlinkOracles['ETH/USD'],
    'invertBase': False,
    'invertQuote': True,
    'sequencerUptimeOracle': ZERO_ADDRESS
}

def main():
    deployer = accounts.load("MAINNET_DEPLOYER")
    # deployer = DEPLOYER
    ezETH = deploy_chainlink_usd_oracle("ezETH", deployer, ezETH_USD)
    weETH = deploy_chainlink_usd_oracle("weETH", deployer, weETH_USD)