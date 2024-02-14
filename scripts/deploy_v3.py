from brownie import accounts, network
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


def main(dryRun=True):
    networkName = network.show_active()
    isFork = False
    if networkName in ["mainnet-fork", "mainnet-current"]:
        networkName = "mainnet"
        isFork = True
    elif networkName in ["arbitrum-fork", "arbitrum-current"]:
        networkName = "arbitrum-one"
        isFork = True
    
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

    deployNotional(deployer, networkName, dryRun, isFork)
    # deployLiquidator(deployer, networkName, dryRun)