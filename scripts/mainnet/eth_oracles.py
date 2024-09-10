from brownie import network
from brownie import ZERO_ADDRESS, accounts
from scripts.deployers.oracle_deployer import deploy_chainlink_usd_oracle, deploy_chainlink_eth_oracle
# from scripts.mainnet.eth_config import ChainlinkOracles, CurrencyDefaults
from scripts.arbitrum.arb_config import ChainlinkOracles, CurrencyDefaults

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

tBTC_ETH = {
    'oracleType': 'ChainlinkAdapter',
    'baseOracle': ChainlinkOracles['tBTC/USD'],
    'quoteOracle': ChainlinkOracles['ETH/USD'],
    'invertBase': False,
    'invertQuote': False,
    'sequencerUptimeOracle': CurrencyDefaults['sequencerUptimeOracle']
}

# WBTC_USD = {
#     'oracleType': 'ChainlinkAdapter',
#     'baseOracle': ChainlinkOracles['WBTC/BTC'],
#     'quoteOracle': ChainlinkOracles['BTC/USD'],
#     'invertBase': False,
#     'invertQuote': True,
#     'sequencerUptimeOracle': ZERO_ADDRESS
# }

# Oracles To List:
# - WBTC/USD: mainnet, trading module
# https://etherscan.io/address/0xa15652067333e979b314735b36AB7582071fa538#readContract
# - tBTC/USD: mainnet, trading module
# https://etherscan.io/address/0x8350b7De6a6a2C1368E7D4Bd968190e13E354297#code
# - tBTC/ETH: mainnet, notional
# https://etherscan.io/address/0xe4d1FBeb9F1898a3107231C83668e684de826CC7#readContract 
# - tBTC/ETH: arbitrum, notional
# https://arbiscan.io/address/0x97Cc93E87655D3d0F41aA0F54f86973fbd4B9Af7#readContract



def main():
    deployer = accounts.load("MAINNET_DEPLOYER")
    # deployer = DEPLOYER
    # Arbitrum
    # https://arbiscan.io/address/0x97Cc93E87655D3d0F41aA0F54f86973fbd4B9Af7#readContract
    tBTC = deploy_chainlink_eth_oracle("tBTC", deployer, tBTC_ETH)

    # Mainnet
    # https://etherscan.io/address/0xa15652067333e979b314735b36AB7582071fa538#readContract
    # WBTC = deploy_chainlink_usd_oracle("WBTC", deployer, WBTC_USD)
    # https://etherscan.io/address/0xe4d1FBeb9F1898a3107231C83668e684de826CC7#readContract
    # tBTC = deploy_chainlink_eth_oracle("tBTC", deployer, tBTC_ETH)
