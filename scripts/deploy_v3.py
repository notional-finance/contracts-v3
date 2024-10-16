from brownie import accounts, network, history
from scripts.deployers.notional_deployer import NotionalDeployer


def deployNotional(deployer, networkName, dryRun, isFork):
    notional = NotionalDeployer(networkName, deployer, dryRun, isFork)
    notional.deployLibs()
    notional.deployActions()
    notional.deployPauseRouter()
    notional.deployRouter()
    notional.deployBeaconImplementation()
    notional.deployAuthorizedCallbacks()

    if isFork:
        notional.upgradeProxy()
    
    return notional

def get_network():
    networkName = network.show_active()
    isFork = False
    if networkName in ["mainnet-fork", "mainnet-current"]:
        networkName = "mainnet"
        isFork = True
    elif networkName in ["arbitrum-fork", "arbitrum-current"]:
        networkName = "arbitrum-one"
        isFork = True

    return (networkName, isFork)

def main(dryRun="LFG"):
    (networkName, isFork) = get_network()
    
    if isFork:
        deployer = accounts[0]
        dryRun = False
    else:
        deployer = accounts.load(networkName.upper() + "_DEPLOYER")
        print("Deployer Address: ", deployer.address)

    if dryRun == "LFG":
        txt = input("Will execute REAL transactions, are you sure (type 'I am sure'): ")
        if txt != "I am sure":
            return
        else:
            dryRun = False

    notional = deployNotional(deployer, networkName, dryRun, isFork)
    # deployLiquidator(deployer, networkName, dryRun)

    gas_used("Contract Deployer", deployer)

def gas_used(label, account, gasPrice = 40):
    print("{}: {:,} gas, {:,.4f} ETH @ {} gwei, {} txns".format(
        label,
        sum([ tx.gas_used for tx in history.from_sender(account) ]),
        sum([ tx.gas_used for tx in history.from_sender(account) ]) * gasPrice * 1e9 / 1e18,
        gasPrice,
        len(history.from_sender(account))
    ))