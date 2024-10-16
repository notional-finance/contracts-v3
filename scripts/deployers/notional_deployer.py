import json
import subprocess

from brownie.network.contract import Contract
from brownie import (
    interface,
    ZERO_ADDRESS,
    AccountAction,
    BatchAction,
    CalculationViews,
    ERC1155Action,
    FreeCollateralExternal,
    GovernanceAction,
    InitializeMarketsAction,
    LiquidateCurrencyAction,
    LiquidatefCashAction,
    PauseRouter,
    Router,
    SettleAssetsExternal,
    TradingAction,
    TreasuryAction,
    VaultAccountAction,
    VaultAction,
    Views,
    nProxy,
    nTokenERC20Proxy,
    PrimeCashProxy,
    PrimeDebtProxy,
    nTokenAction,
    nTokenMintAction,
    nTokenRedeemAction,
    VaultLiquidationAction,
    VaultAccountHealth,
    LeveragedNTokenAdapter
)
from brownie.network import web3
from scripts.common import loadContractFromABI
from scripts.deployers.contract_deployer import ContractDeployer
from scripts.deployment import deployArtifact


class NotionalDeployer:
    def __init__(self, network, deployer, dryRun, isFork=False, config=None, persist=True) -> None:
        self.config = config
        self.network = network
        if isFork:
            self.persist = False
        else:
            self.persist = True
        self.libs = {}
        self.actions = {}
        self.routers = {}
        self.notional = None
        self.deployer = deployer
        self.dryRun = dryRun
        self.isFork = isFork
        self._load()

    def verify(self, contract, deployed, args = []):
        if self.dryRun or self.isFork:
            return
        print("Verifying {} at {} with args {}".format(contract._name, deployed.address, args))
        output = subprocess.check_output([
            "npx", "hardhat", "verify",
            "--network", self.network,
            deployed.address
        ] + args, encoding='utf-8')
        print(output)

    def _load(self):
        if self.config is None:
            with open("v3.{}.json".format(self.network), "r") as f:
                self.config = json.load(f)
        if "libs" in self.config:
            self.libs = self.config["libs"]
        if "actions" in self.config:
            self.actions = self.config["actions"]
        if "routers" in self.config:
            self.routers = self.config["routers"]
        if "beacons" in self.config:
            self.beacons = self.config["beacons"]
        if "callbacks" in self.config:
            self.callbacks = self.config["callbacks"]
        if "notional" in self.config:
            self.notional = self.config["notional"]
            self.proxy = loadContractFromABI(
                "NotionalProxy", self.config["notional"], "abi/Notional.json"
            )

    def _save(self):
        self.config["libs"] = self.libs
        self.config["actions"] = self.actions
        self.config["routers"] = self.routers
        self.config["beacons"] = self.beacons
        self.config["callbacks"] = self.callbacks
        if self.notional is not None:
            self.config["notional"] = self.notional
        if self.persist:
            with open("v3.{}.json".format(self.network), "w") as f:
                json.dump(self.config, f, sort_keys=True, indent=4)

    def _deployLib(self, deployer, contract):
        if contract._name in self.libs:
            print("{} deployed at {}".format(contract._name, self.libs[contract._name]))
            # Adds the lib into the state in case it does not exist yet, prevents a lib not found
            # error in brownie
            contract.at(self.libs[contract._name])
            return

        # Make sure isLib is set to true
        # This ensures that map.json only contains 1 copy of the lib
        if self.dryRun:
            print("Will deploy library {}".format(contract._name))
        else:
            deployed = deployer.deploy(contract, [], "", True, True)
            self.libs[contract._name] = deployed.address
            self._save()
            self.verify(contract, deployed)

    def deployLibs(self):
        deployer = ContractDeployer(self.deployer, {}, self.libs)
        self._deployLib(deployer, SettleAssetsExternal)
        self._deployLib(deployer, FreeCollateralExternal)
        self._deployLib(deployer, TradingAction)
        self._deployLib(deployer, nTokenMintAction)
        self._deployLib(deployer, nTokenRedeemAction)

    def _deployAction(self, deployer, contract, args=None):
        if contract._name in self.actions:
            print("{} deployed at {}".format(contract._name, self.actions[contract._name]))
            return

        if self.dryRun:
            print("Will deploy action contract {}".format(contract._name))
        else:
            deployed = deployer.deploy(contract, args, "", True)
            self.actions[contract._name] = deployed.address
            self._save()
            self.verify(contract, deployed, [] if args is None else args)

    def deployAction(self, action, args=None):
        deployer = ContractDeployer(self.deployer, self.actions, self.libs)
        self._deployAction(deployer, action, args)

    def deployActions(self):
        deployer = ContractDeployer(self.deployer, self.actions, self.libs)
        self._deployAction(deployer, GovernanceAction)
        self._deployAction(deployer, Views)
        self._deployAction(deployer, InitializeMarketsAction)
        self._deployAction(deployer, nTokenAction)
        self._deployAction(deployer, BatchAction)
        self._deployAction(deployer, AccountAction)
        self._deployAction(deployer, ERC1155Action)
        self._deployAction(deployer, LiquidateCurrencyAction)
        self._deployAction(deployer, CalculationViews)
        self._deployAction(deployer, LiquidatefCashAction)
        self._deployAction(deployer, TreasuryAction)
        self._deployAction(deployer, VaultAction)
        self._deployAction(deployer, VaultAccountAction)
        self._deployAction(deployer, VaultLiquidationAction)
        self._deployAction(deployer, VaultAccountHealth)

    def _deployRouter(self, deployer, contract, args=[]):
        if contract._name in self.routers:
            print("{} deployed at {}".format(contract._name, self.routers[contract._name]))
            return

        if contract._name == "Router":
            printArgs = {
                n["name"]: args[0][i]
                for (i, n) in enumerate(contract.deploy.abi["inputs"][0]["components"])
            }
        else:
            printArgs = {
                n["name"]: args[i]
                for (i, n) in enumerate(contract.deploy.abi["inputs"])
            }

        if self.dryRun:
            print("Will deploy {} with args:".format(contract._name))
            # Print this for hardhat verification
            print(printArgs)
        else:
            deployed = deployer.deploy(contract, args, "", True)
            print("Deployed {} with args:".format(contract._name))
            print(printArgs)

            self.routers[contract._name] = deployed.address
            self._save()
            self.verify(contract, deployed, args)

    def deployPauseRouter(self):
        deployer = ContractDeployer(self.deployer, self.routers)
        self._deployRouter(
            deployer,
            PauseRouter,
            [
                self.actions["Views"],
                self.actions["LiquidateCurrencyAction"],
                self.actions["LiquidatefCashAction"],
                self.actions["CalculationViews"],
                self.actions["VaultAccountHealth"],
            ],
        )

    def deployRouter(self):
        deployer = ContractDeployer(self.deployer, self.routers)
        self._deployRouter(
            deployer,
            Router,
            [
                (
                    self.actions["GovernanceAction"],
                    self.actions["Views"],
                    self.actions["InitializeMarketsAction"],
                    self.actions["nTokenAction"],
                    self.actions["BatchAction"],
                    self.actions["AccountAction"],
                    self.actions["ERC1155Action"],
                    self.actions["LiquidateCurrencyAction"],
                    self.actions["LiquidatefCashAction"],
                    self.actions["TreasuryAction"],
                    self.actions["CalculationViews"],
                    self.actions["VaultAccountAction"],
                    self.actions["VaultAction"],
                    self.actions["VaultLiquidationAction"],
                    self.actions["VaultAccountHealth"],
                )
            ],
        )

    def _deployBeaconImplementation(self, deployer, contract):
        args = [self.notional]
        if contract._name in self.beacons:
            print("{} deployed at {}".format(contract._name, self.beacons[contract._name]))
            return

        if self.dryRun:
            print("Will deploy {} with args {}".format(contract._name, args))
        else:
            deployed = deployer.deploy(contract, args, "", True)
            print("Deployed beacon implementation {} with args:".format(contract._name))

            self.beacons[contract._name] = deployed.address
            self._save()
            self.verify(contract, deployed, args)

    def deployBeaconImplementation(self):
        deployer = ContractDeployer(self.deployer, self.beacons)
        self._deployBeaconImplementation(deployer, nTokenERC20Proxy)
        self._deployBeaconImplementation(deployer, PrimeCashProxy)
        self._deployBeaconImplementation(deployer, PrimeDebtProxy)

    def _deployCallback(self, deployer, contract, args):
        if contract._name in self.callbacks:
            print("{} deployed at {}".format(contract._name, self.callbacks[contract._name]))
            return

        if self.dryRun:
            print("Will deploy {} with args {}".format(contract._name, args))
        else:
            deployed = deployer.deploy(contract, args, "", True)
            print("Deployed callback {} with args:".format(contract._name))

            self.callbacks[contract._name] = deployed.address
            self._save()
            self.verify(contract, deployed, args)

    def deployAuthorizedCallbacks(self):
        deployer = ContractDeployer(self.deployer, self.callbacks)
        self._deployCallback(deployer, LeveragedNTokenAdapter, [self.notional])

    def upgradeProxy(self):
        if self.isFork:
            print("Upgrading router to {}".format(self.routers["Router"]))
            n = Contract.from_abi("Notional", self.proxy, abi=interface.NotionalProxy.abi)
            self.proxy.upgradeTo(self.routers["Router"], {"from": n.owner()})

    def deployProxy(self):
        # Already deployed
        if self.notional is not None:
            print("Notional deployed at {}".format(self.notional))
            # Check if proxy needs to be upgraded
            impl = self.proxy.getImplementation()
            if impl != self.routers["Router"]:
                self.upgradeProxy(impl)
            else:
                print("Router is up to date")
            return

        deployer = ContractDeployer(self.deployer)
        initializeData = web3.eth.contract(abi=Router.abi).encodeABI(
            fn_name="initialize",
            args=[self.deployer.address, self.routers["PauseRouter"], self.routers["Router"]],
        )
        contract = deployer.deploy(nProxy, [self.routers["Router"], initializeData], "", True)
        self.notional = contract.address
        self._save()
