from brownie import ZERO_ADDRESS, accounts
from scripts.deployers.deploy_oracle import deploy_chainlink_usd_oracle
from scripts.mainnet.eth_config import ChainlinkOracles, ListedTokens

DEPLOYER = "0x8B64fA5Fd129df9c755eB82dB1e16D6D0Bdf5Bc3"

def main():
    deployer = accounts.at(DEPLOYER, force=True)
    wbtc = deploy_chainlink_usd_oracle("WBTC", deployer, ListedTokens['WBTC']['usdOracle'])
    rETH = deploy_chainlink_usd_oracle("rETH", deployer, ListedTokens['rETH']['usdOracle'])
    osETH = deploy_chainlink_usd_oracle("osETH", deployer, {
        "oracleType": "ChainlinkAdapter",
        "baseOracle": ChainlinkOracles["osETH/ETH"],
        "quoteOracle": ChainlinkOracles["ETH/USD"],
        "invertBase": False,
        "invertQuote": True,
        "sequencerUptimeOracle": ZERO_ADDRESS
    })
