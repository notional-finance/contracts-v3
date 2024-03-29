from brownie.convert import to_int
from brownie.convert.datatypes import HexString

# Jan 1 2021
START_TIME = 1609459200
SECONDS_IN_DAY = 86400
SECONDS_IN_YEAR = SECONDS_IN_DAY * 360
SECONDS_IN_QUARTER = SECONDS_IN_DAY * 90
SECONDS_IN_MONTH = SECONDS_IN_DAY * 30
RATE_PRECISION = 1e9
TOKEN_PRECISION = 1e8
BASIS_POINT = RATE_PRECISION / 10000
NORMALIZED_RATE_TIME = 31104000
START_TIME_TREF = START_TIME - START_TIME % (90 * SECONDS_IN_DAY)
SETTLEMENT_DATE = START_TIME_TREF + (90 * SECONDS_IN_DAY)
FCASH_ASSET_TYPE = 1
REPO_INCENTIVE = 10
PRIME_CASH_VAULT_MATURITY = 2 ** 40 - 1

PORTFOLIO_FLAG = HexString("0x8000", "bytes2")
BALANCE_FLAG = HexString("0x4000", "bytes2")
PORTFOLIO_FLAG_INT = to_int(HexString("0x8000", "bytes2"), "int")
BALANCE_FLAG_INT = to_int(HexString("0x4000", "bytes2"), "int")
HAS_ASSET_DEBT = "0x01"
HAS_CASH_DEBT = "0x02"
HAS_BOTH_DEBT = "0x03"

MARKETS = [
    START_TIME_TREF + 90 * SECONDS_IN_DAY,
    START_TIME_TREF + 180 * SECONDS_IN_DAY,
    START_TIME_TREF + SECONDS_IN_YEAR,
    START_TIME_TREF + 2 * SECONDS_IN_YEAR,
    START_TIME_TREF + 5 * SECONDS_IN_YEAR,
    START_TIME_TREF + 10 * SECONDS_IN_YEAR,
    START_TIME_TREF + 20 * SECONDS_IN_YEAR,
]

CASH_GROUP_PARAMETERS = (
    7,   # 0: Max Market Index
    10,  # 1: time window, 10 min
    10,  # 2: max discount rate, 50 BPS (max discount 99.5)
    30,  # 3: reserve fee share, percentage
    6,   # 4: debt buffer 150 bps
    6,   # 5: fcash haircut 150 bps
    0,   # 6: min oracle rate 25 bps
    4,   # 7: liquidation discount 100 bps
    4,   # 8: liquidation debt buffer 100 bps
    255, # 9: max oracle rate
)

CURVE_SHAPES = {
    "flat": {
        "rates": [
            r * RATE_PRECISION for r in [0.03, 0.035, 0.04, 0.05, 0.06, 0.07, 0.08, 0.09, 0.10]
        ],
        "proportion": 0.33,
    },
    "normal": {
        "rates": [
            r * RATE_PRECISION for r in [0.06, 0.065, 0.07, 0.08, 0.09, 0.10, 0.11, 0.12, 0.13]
        ],
        "proportion": 0.5,
    },
    "high": {
        "rates": [
            r * RATE_PRECISION for r in [0.08, 0.09, 0.10, 0.11, 0.12, 0.13, 0.14, 0.15, 0.16]
        ],
        "proportion": 0.8,
    },
}

DEPOSIT_ACTION_TYPE = {
    "None": 0,
    "DepositAsset": 1,
    "DepositUnderlying": 2,
    "DepositAssetAndMintNToken": 3,
    "DepositUnderlyingAndMintNToken": 4,
    "RedeemNToken": 5,
    "ConvertCashToNToken": 6,
}

TRADE_ACTION_TYPE = {
    "Lend": 0,
    "Borrow": 1,
    "AddLiquidity": 2,
    "RemoveLiquidity": 3,
    "PurchaseNTokenResidual": 4,
    "SettleCashDebt": 5,
}

ZERO_ADDRESS = HexString(0, type_str="bytes20")
SETTLEMENT_RESERVE = "0x00000000000000000000000000000000000005e7"
FEE_RESERVE = "0x0000000000000000000000000000000000000FEE"
