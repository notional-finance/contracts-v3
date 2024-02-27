from brownie import (
    ZERO_ADDRESS,
    ChainlinkAdapter,
    ERC4626OracleAdapter,
    wstETHOracleAdapter,
)

def deploy_chainlink_usd_oracle(symbol, deployer, oracle):
    if isinstance(oracle, str):
        return ChainlinkAdapter.at(oracle)
    elif oracle["oracleType"] == "ChainlinkAdapter":
        return ChainlinkAdapter.deploy(
            oracle['baseOracle'],
            oracle['quoteOracle'],
            oracle['invertBase'],
            oracle['invertQuote'],
            "Notional {}/USD Chainlink Adapter".format(symbol),
            oracle['sequencerUptimeOracle'],
            {"from": deployer}
        )


def deploy_chainlink_oracle(symbol, deployer, config):
    token = config[symbol]
    if symbol == "ETH":
        return ZERO_ADDRESS
    elif "ethOracle" in token and token["ethOracle"]:
        return ChainlinkAdapter.at(token["ethOracle"])
    elif "oracleType" in token and token["oracleType"] == "ERC4626":
        return ERC4626OracleAdapter.deploy(
            token['baseOracle'],
            token['quoteOracle'],
            token['invertBase'],
            token['invertQuote'],
            "Notional {} Chainlink Adapter".format(symbol),
            token['sequencerUptimeOracle'],
            {"from": deployer}
        )
    elif "oracleType" in token and token["oracleType"] == "wstETH":
        return wstETHOracleAdapter.deploy(
            token['baseOracle'],
            token['invertBase'],
            token['invertQuote'],
            "Notional {} Chainlink Adapter".format(symbol),
            {"from": deployer}
        )
    else:
        return ChainlinkAdapter.deploy(
            token['baseOracle'],
            token['quoteOracle'],
            token['invertBase'],
            token['invertQuote'],
            "Notional {} Chainlink Adapter".format(symbol),
            token['sequencerUptimeOracle'],
            {"from": deployer}
        )
