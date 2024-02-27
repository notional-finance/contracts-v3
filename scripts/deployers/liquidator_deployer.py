from brownie import accounts, FlashLiquidator, Contract, interface
from scripts.inspect import get_addresses

DEPLOYER = "0x8B64fA5Fd129df9c755eB82dB1e16D6D0Bdf5Bc3"

def main():
    (addresses, notional, *_) = get_addresses()
    deployer = accounts.at(DEPLOYER, force=True)

    liquidator = FlashLiquidator.deploy(
        notional.address,
        addresses["aaveLendingPool"],
        addresses["tokens"]["WETH"]["address"],
        deployer,
        addresses["tradingModule"],
        {"from": deployer}
    )

    liquidator.enableCurrencies([1,2,3,4], {"from": deployer})
    tradingModule = Contract.from_abi("trading", addresses["tradingModule"], interface.ITradingModule.abi)
    # tradingModule.setTokenPermissions(
    #     liquidator,
    #     token['address'],
    #     (True, 8, 15), # allow sell, 8 is 0x, 15 is all trade types
    #     {"from": notional.owner()}
    # )
