from brownie import ZERO_ADDRESS

ChainlinkOracles = {
    "ETH/USD": "0x639fe6ab55c921f74e7fac1ee960c0b6293ba612",
    "USDC/USD": "0x50834f3163758fcc1df9973b6e91f0f0f0434ad3",
    "DAI/USD": "0xc5c8e77b397e531b8ec06bfb0048328b30e9ecfb",
    "WBTC/USD": "0xd0c7101eacbb49f3decccc166d238410d6d46d57",
    "FRAX/USD": "0x0809e3d38d1b4214958faf06d8b1b1a2b73f2ab8",
    "stETH/ETH": "0xded2c52b75b24732e9107377b7ba93ec1ffa4baf",
    "wstETH/stETH": "0xb1552c5e96b312d0bf8b554186f846c40614a540",
    "rETH/ETH": "0xD6aB2298946840262FcC278fF31516D39fF611eF",
    "USDT/USD": "0x3f3f5df88dc9f13eac63df89ec16ef6e7e25dde7",
    "cbETH/ETH": "0xa668682974e3f121185a3cd94f00322bec674275",
    "GMX/USD": "0xdb98056fecfff59d032ab628337a4887110df3db",
    "ARB/USD": "0xb2a824043730fe05f3da2efafa1cbbe83fa548d6",
    "RDNT/USD": "0x20d0fcab0ecfd078b036b6caf1fac69a6453b352",
    "LINK/USD": "0x86e53cf1b870786351da77a57575e79cb55812cb",
    "UNI/USD": "0x9c917083fdb403ab5adbec26ee294f6ecada2720",
    "LDO/USD": "0xa43a34030088e6510feccfb77e88ee5e7ed0fe64",
    "ezETH/ETH": "0x11E1836bFF2ce9d6A5bec9cA79dc998210f3886d",
    "weETH/ETH": "0xE141425bc1594b8039De6390db1cDaf4397EA22b",
    "rsETH/ETH": "0xb0EA543f9F8d4B818550365d13F66Da747e1476A",
    "tBTC/USD": "0xE808488e8627F6531bA79a13A9E0271B39abEb1C",
}

CurrencyDefaults = {
    "sequencerUptimeOracle": "0xfdb631f5ee196f0ed6faa767959853a9f217697d",

    # Cash Group
    "maxMarketIndex": 2,
    "primeRateOracleTimeWindow5Min": 72,
    "maxDiscountFactor": 40,
    "reserveFeeShare": 80,
    "fCashHaircut": 22,
    "debtBuffer": 22,
    "minOracleRate": 20,
    "liquidationfCashDiscount": 6,
    "liquidationDebtBuffer": 6,
    "maxOracleRate": 28,

    # nToken
    "residualPurchaseIncentive": 20,
    "pvHaircutPercentage": 90,
    "residualPurchaseTimeBufferHours": 24,
    'cashWithholdingBuffer10BPS': 20,
    "liquidationHaircutPercentage": 98,

    "rateOracleTimeWindow": 72,
    "allowDebt": True
}

PrimeOnlyDefaults = {
    "sequencerUptimeOracle": "0xfdb631f5ee196f0ed6faa767959853a9f217697d",
    "primeRateOracleTimeWindow5Min": 72,
}

ListedTokens = {
    "ETH": CurrencyDefaults | {
        "address": ZERO_ADDRESS,
        "name": "Ether",
        "decimals": 18,

        "buffer": 124,
        "haircut": 81,
        "liquidationDiscount": 106,
        "maxUnderlyingSupply": 10e8,

        # Prime Cash Curve
        "primeCashCurve": {
            "kinkUtilization1": 15,
            "kinkUtilization2": 70,
            "kinkRate1": 2,
            "kinkRate2": 8,
            "maxRate25BPS": 255,
            "feeRatePercent": 20,
            "minFeeRate5BPS": 10,
            "maxFeeRate25BPS": 160
        },

        # fCash Curve
        "fCashCurves" : [{
            "kinkUtilization1": 15,
            "kinkUtilization2": 70,
            "kinkRate1": 17,
            "kinkRate2": 51,
            "maxRate25BPS": 120,
            "feeRatePercent": 8,
            "minFeeRate5BPS": 3,
            "maxFeeRate25BPS": 8
        }, {
            "kinkUtilization1": 15,
            "kinkUtilization2": 70,
            "kinkRate1": 20,
            "kinkRate2": 61,
            "maxRate25BPS": 100,
            "feeRatePercent": 8,
            "minFeeRate5BPS": 3,
            "maxFeeRate25BPS": 8
        }],

        "proportion": [0.5e9, 0.5e9],
        "depositShare": [0.55e8, 0.45e8],
        "leverageThreshold": [0.7e9, 0.7e9],
    },
    "DAI": CurrencyDefaults | {
        "address": "0xDA10009cBd5D07dd0CeCc66161FC93D7c9000da1",
        "name": "Dai Stablecoin",
        "decimals": 18,
        "baseOracle": ChainlinkOracles["DAI/USD"],
        "quoteOracle": ChainlinkOracles["ETH/USD"],
        "invertBase": False,
        "invertQuote": False,

        "buffer": 109,
        "haircut": 92,
        "liquidationDiscount": 104,
        "maxUnderlyingSupply": 10_000e8,

        # Prime Cash Curve
        "primeCashCurve": {
            "kinkUtilization1": 10,
            "kinkUtilization2": 80,
            "kinkRate1": 5,
            "kinkRate2": 16,
            "maxRate25BPS": 192,
            "feeRatePercent": 20,
            "minFeeRate5BPS": 10,
            "maxFeeRate25BPS": 80
        },

        # fCash Curve
        "fCashCurves" : [{
            "kinkUtilization1": 15,
            "kinkUtilization2": 80,
            "kinkRate1": 17,
            "kinkRate2": 51,
            "maxRate25BPS": 120,
            "feeRatePercent": 8,
            "minFeeRate5BPS": 3,
            "maxFeeRate25BPS": 8
        }, {
            "kinkUtilization1": 15,
            "kinkUtilization2": 80,
            "kinkRate1": 20,
            "kinkRate2": 61,
            "maxRate25BPS": 100,
            "feeRatePercent": 8,
            "minFeeRate5BPS": 3,
            "maxFeeRate25BPS": 8
        }],

        "proportion": [0.5e9, 0.5e9],
        "depositShare": [0.55e8, 0.45e8],
        "leverageThreshold": [0.8e9, 0.8e9],
    },
    "USDC": CurrencyDefaults | {
        "address": "0xaf88d065e77c8cC2239327C5EDb3A432268e5831",
        "name": "USD Coin",
        "decimals": 6,
        "baseOracle": ChainlinkOracles["USDC/USD"],
        "quoteOracle": ChainlinkOracles["ETH/USD"],
        "invertBase": False,
        "invertQuote": False,

        "buffer": 109,
        "haircut": 92,
        "liquidationDiscount": 104,
        "maxUnderlyingSupply": 10_000e8,

        # Prime Cash Curve
        "primeCashCurve": {
            "kinkUtilization1": 10,
            "kinkUtilization2": 80,
            "kinkRate1": 5,
            "kinkRate2": 16,
            "maxRate25BPS": 192,
            "feeRatePercent": 20,
            "minFeeRate5BPS": 10,
            "maxFeeRate25BPS": 80
        },

        # fCash Curve
        "fCashCurves" : [{
            "kinkUtilization1": 15,
            "kinkUtilization2": 80,
            "kinkRate1": 17,
            "kinkRate2": 51,
            "maxRate25BPS": 120,
            "feeRatePercent": 8,
            "minFeeRate5BPS": 3,
            "maxFeeRate25BPS": 8
        }, {
            "kinkUtilization1": 15,
            "kinkUtilization2": 80,
            "kinkRate1": 20,
            "kinkRate2": 61,
            "maxRate25BPS": 100,
            "feeRatePercent": 8,
            "minFeeRate5BPS": 3,
            "maxFeeRate25BPS": 8
        }],

        "proportion": [0.5e9, 0.5e9],
        "depositShare": [0.55e8, 0.45e8],
        "leverageThreshold": [0.8e9, 0.8e9],
    },
    "WBTC": CurrencyDefaults | {
        "address": "0x2f2a2543B76A4166549F7aaB2e75Bef0aefC5B0f",
        "name": "Wrapped BTC",
        "decimals": 8,
        "baseOracle": ChainlinkOracles["WBTC/USD"],
        "quoteOracle": ChainlinkOracles["ETH/USD"],
        "invertBase": False,
        "invertQuote": False,
        "minOracleRate": 16,
        "maxOracleRate": 20,

        "buffer": 124,
        "haircut": 81,
        "liquidationDiscount": 107,
        "maxUnderlyingSupply": 0.50e8,

        # Prime Cash Curve
        "primeCashCurve": {
            "kinkUtilization1": 15,
            "kinkUtilization2": 70,
            "kinkRate1": 1,
            "kinkRate2": 6,
            "maxRate25BPS": 255,
            "feeRatePercent": 20,
            "minFeeRate5BPS": 10,
            "maxFeeRate25BPS": 160
        },

        # fCash Curve
        "fCashCurves" : [{
            "kinkUtilization1": 15,
            "kinkUtilization2": 70,
            "kinkRate1": 4,
            "kinkRate2": 34,
            "maxRate25BPS": 120,
            "feeRatePercent": 8,
            "minFeeRate5BPS": 3,
            "maxFeeRate25BPS": 8
        }, {
            "kinkUtilization1": 15,
            "kinkUtilization2": 70,
            "kinkRate1": 5,
            "kinkRate2": 41,
            "maxRate25BPS": 100,
            "feeRatePercent": 8,
            "minFeeRate5BPS": 3,
            "maxFeeRate25BPS": 8
        }],

        "proportion": [0.5e9, 0.5e9],
        "depositShare": [0.50e8, 0.50e8],
        "leverageThreshold": [0.7e9, 0.7e9],
    },
    "wstETH": CurrencyDefaults | {
        "address": "0x5979D7b546E38E414F7E9822514be443A4800529",
        "name": "Wrapped Liquid Staked Ether",
        "decimals": 18,

        "baseOracle": ChainlinkOracles["wstETH/stETH"],
        "quoteOracle": ChainlinkOracles["stETH/ETH"],
        "invertBase": False,
        "invertQuote": True,
        "minOracleRate": 8,
        "maxOracleRate": 12,

        "buffer": 129,
        "haircut": 78,
        "liquidationDiscount": 106,
        "maxUnderlyingSupply": 10e8,

        # Prime Cash Curve
        "primeCashCurve": {
            "kinkUtilization1": 15,
            "kinkUtilization2": 70,
            "kinkRate1": 1,
            "kinkRate2": 3,
            "maxRate25BPS": 255,
            "feeRatePercent": 20,
            "minFeeRate5BPS": 10,
            "maxFeeRate25BPS": 160
        },

        # fCash Curve
        "fCashCurves" : [{
            "kinkUtilization1": 15,
            "kinkUtilization2": 70,
            "kinkRate1": 2,
            "kinkRate2": 17,
            "maxRate25BPS": 120,
            "feeRatePercent": 8,
            "minFeeRate5BPS": 3,
            "maxFeeRate25BPS": 8
        }, {
            "kinkUtilization1": 15,
            "kinkUtilization2": 70,
            "kinkRate1": 2,
            "kinkRate2": 21,
            "maxRate25BPS": 100,
            "feeRatePercent": 8,
            "minFeeRate5BPS": 3,
            "maxFeeRate25BPS": 8
        }],

        "proportion": [0.5e9, 0.5e9],
        "depositShare": [0.50e8, 0.50e8],
        "leverageThreshold": [0.7e9, 0.7e9],
    },
    "FRAX": CurrencyDefaults | {
        "address": "0x17FC002b466eEc40DaE837Fc4bE5c67993ddBd6F",
        "name": "Frax",
        "decimals": 18,
        "baseOracle": ChainlinkOracles["FRAX/USD"],
        "quoteOracle": ChainlinkOracles["ETH/USD"],
        "invertBase": False,
        "invertQuote": False,

        "buffer": 109,
        "haircut": 0,
        "liquidationDiscount": 104,
        "maxUnderlyingSupply": 10_000e8,

        # Prime Cash Curve
        "primeCashCurve": {
            "kinkUtilization1": 10,
            "kinkUtilization2": 80,
            "kinkRate1": 5,
            "kinkRate2": 16,
            "maxRate25BPS": 192,
            "feeRatePercent": 20,
            "minFeeRate5BPS": 10,
            "maxFeeRate25BPS": 80
        },

        # fCash Curve
        "fCashCurves" : [{
            "kinkUtilization1": 15,
            "kinkUtilization2": 80,
            "kinkRate1": 17,
            "kinkRate2": 51,
            "maxRate25BPS": 120,
            "feeRatePercent": 8,
            "minFeeRate5BPS": 3,
            "maxFeeRate25BPS": 8
        }, {
            "kinkUtilization1": 15,
            "kinkUtilization2": 80,
            "kinkRate1": 20,
            "kinkRate2": 61,
            "maxRate25BPS": 100,
            "feeRatePercent": 8,
            "minFeeRate5BPS": 3,
            "maxFeeRate25BPS": 8
        }],

        "proportion": [0.5e9, 0.5e9],
        "depositShare": [0.55e8, 0.45e8],
        "leverageThreshold": [0.8e9, 0.8e9],
    },
    "rETH": CurrencyDefaults | {
        "address": "0xEC70Dcb4A1EFa46b8F2D97C310C9c4790ba5ffA8",
        "name": "Rocket Pool ETH",
        "decimals": 18,
        "ethOracle": ChainlinkOracles["rETH/ETH"],
        "pCashOracle": "0x164DF1D4C0dfE877e5C75f2A7b0dCC3d83190E19",

        "maxOracleRate25BPS": 12,

        "buffer": 129,
        "haircut": 76,
        "liquidationDiscount": 107,
        "maxUnderlyingSupply": 10e8,

        # Prime Cash Curve
        "primeCashCurve": {
            "kinkUtilization1": 50,
            "kinkUtilization2": 75,
            "kinkRate1": 1,
            "kinkRate2": 4,
            "maxRate25BPS": 255,
            "feeRatePercent": 20,
            "minFeeRate5BPS": 10,
            "maxFeeRate25BPS": 160
        },

        # fCash Curve
        "fCashCurves" : [{
            "kinkUtilization1": 15,
            "kinkUtilization2": 75,
            "kinkRate1": 5,
            "kinkRate2": 15,
            "maxRate25BPS": 120,
            "feeRatePercent": 8,
            "minFeeRate5BPS": 2,
            "maxFeeRate25BPS": 8
        }, {
            "kinkUtilization1": 15,
            "kinkUtilization2": 75,
            "kinkRate1": 6,
            "kinkRate2": 18,
            "maxRate25BPS": 100,
            "feeRatePercent": 8,
            "minFeeRate5BPS": 2,
            "maxFeeRate25BPS": 8
        }],

        "proportion": [0.5e9, 0.5e9],
        "depositShare": [0.5e8, 0.5e8],
        "leverageThreshold": [0.75e9, 0.75e9],
    },
    "USDT": CurrencyDefaults | {
        "address": "0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9",
        "name": "Tether USD",
        "decimals": 6,
        "baseOracle": ChainlinkOracles["USDT/USD"],
        "quoteOracle": ChainlinkOracles["ETH/USD"],
        "invertBase": False,
        "invertQuote": False,
        "pCashOracle": "0x7c8488771e60e07ef222213E1cc620582fC9fe67",
        "ethOracle": "0x24fa92Cd21Bd3eBa1C07877593D0a75326bD35D6",

        "buffer": 109,
        "haircut": 86,
        "liquidationDiscount": 104,
        "maxUnderlyingSupply": 10_000e8,

        # Prime Cash Curve
        "primeCashCurve": {
            "kinkUtilization1": 10,
            "kinkUtilization2": 80,
            "kinkRate1": 5,
            "kinkRate2": 12,
            "maxRate25BPS": 192,
            "feeRatePercent": 20,
            "minFeeRate5BPS": 10,
            "maxFeeRate25BPS": 80
        },

        # fCash Curve
        "fCashCurves" : [{
            "kinkUtilization1": 15,
            "kinkUtilization2": 80,
            "kinkRate1": 17,
            "kinkRate2": 51,
            "maxRate25BPS": 120,
            "feeRatePercent": 8,
            "minFeeRate5BPS": 3,
            "maxFeeRate25BPS": 8
        }, {
            "kinkUtilization1": 15,
            "kinkUtilization2": 80,
            "kinkRate1": 20,
            "kinkRate2": 61,
            "maxRate25BPS": 100,
            "feeRatePercent": 8,
            "minFeeRate5BPS": 3,
            "maxFeeRate25BPS": 8
        }],

        "proportion": [0.5e9, 0.5e9],
        "depositShare": [0.55e8, 0.45e8],
        "leverageThreshold": [0.8e9, 0.8e9],
    },
    'cbETH': CurrencyDefaults | {
        "address": "0x1DEBd73E752bEaF79865Fd6446b0c970EaE7732f",
        "name": "Coinbase Wrapped Staked ETH",
        "decimals": 18,
        "ethOracle": ChainlinkOracles["cbETH/ETH"],
        "pCashOracle": "0x07F035160f0cE5158fcDe86C7F028B25c84D15c8",

        "buffer": 129,
        "haircut": 78,
        "liquidationDiscount": 107,
        "maxUnderlyingSupply": 650e8,

        # Prime Cash Curve
        "primeCashCurve": {
            "kinkUtilization1": 50,
            "kinkUtilization2": 70,
            "kinkRate1": 1,
            "kinkRate2": 2,
            "maxRate25BPS": 225,
            "feeRatePercent": 20,
            "minFeeRate5BPS": 10,
            "maxFeeRate25BPS": 160
        },

        # fCash Curve
        "fCashCurves" : [{
            "kinkUtilization1": 15,
            "kinkUtilization2": 70,
            "kinkRate1": 5,
            "kinkRate2": 15,
            "maxRate25BPS": 120,
            "feeRatePercent": 8,
            "minFeeRate5BPS": 2,
            "maxFeeRate25BPS": 8
        }, {
            "kinkUtilization1": 15,
            "kinkUtilization2": 70,
            "kinkRate1": 5,
            "kinkRate2": 15,
            "maxRate25BPS": 100,
            "feeRatePercent": 8,
            "minFeeRate5BPS": 2,
            "maxFeeRate25BPS": 8
        }],

        "proportion": [0.5e9, 0.5e9],
        "depositShare": [0.5e8, 0.5e8],
        "leverageThreshold": [0.7e9, 0.7e9],
    },
    'GMX': PrimeOnlyDefaults | {
        "address": "0xfc5A1A6EB076a2C7aD06eD22C90d7E710E35ad0a",
        "name": "GMX",
        "decimals": 18,
        "baseOracle": ChainlinkOracles["GMX/USD"],
        "quoteOracle": ChainlinkOracles["ETH/USD"],
        "invertBase": False,
        "invertQuote": False,
        "pCashOracle": "0x4fc0f4badfbE8107E810f42E0D5BAC20D6A0294E",
        "ethOracle": "0x4d761abc3178fd94965a3Aecfc007FFD1b82b6fb",

        "allowDebt": True,
        "buffer": 156,
        "haircut": 64,
        "liquidationDiscount": 108,
        "maxUnderlyingSupply": 14_000e8,

        # Prime Cash Curve
        "primeCashCurve": {
            "kinkUtilization1": 15,
            "kinkUtilization2": 70,
            "kinkRate1": 1,
            "kinkRate2": 3,
            "maxRate25BPS": 225,
            "feeRatePercent": 20,
            "minFeeRate5BPS": 10,
            "maxFeeRate25BPS": 160
        },
    },
    'ARB': PrimeOnlyDefaults | {
        "address": "0x912CE59144191C1204E64559FE8253a0e49E6548",
        "name": "Arbitrum",
        "decimals": 18,
        "baseOracle": ChainlinkOracles["ARB/USD"],
        "quoteOracle": ChainlinkOracles["ETH/USD"],
        "invertBase": False,
        "invertQuote": False,
        "pCashOracle": "0x764739A9C951795FAa2DFeFF5B2bbb8e85025980",
        "ethOracle": "0x432D8B634a80e03568276190bB859f2E5Aa38003",

        "allowDebt": True,
        "buffer": 147,
        "haircut": 68,
        "liquidationDiscount": 108,
        "maxUnderlyingSupply": 1_200_000e8,

        # Prime Cash Curve
        "primeCashCurve": {
            "kinkUtilization1": 15,
            "kinkUtilization2": 70,
            "kinkRate1": 1,
            "kinkRate2": 3,
            "maxRate25BPS": 225,
            "feeRatePercent": 20,
            "minFeeRate5BPS": 10,
            "maxFeeRate25BPS": 160
        },
    },
    'RDNT': PrimeOnlyDefaults | {
        "address": "0x3082CC23568eA640225c2467653dB90e9250AaA0",
        "name": "Radiant",
        "decimals": 18,
        "baseOracle": ChainlinkOracles["RDNT/USD"],
        "quoteOracle": ChainlinkOracles["ETH/USD"],
        "invertBase": False,
        "invertQuote": False,
        "pCashOracle": "0x6Ebf8521a0691703DA4157c5C9eF3baD9D80534E",
        "ethOracle": "0x676F3AA7d085B44ecDB41d11B56d9F90145848CE",

        "allowDebt": True,
        "buffer": 156,
        "haircut": 64,
        "liquidationDiscount": 108,
        "maxUnderlyingSupply": 1_250_000e8,

        # Prime Cash Curve
        "primeCashCurve": {
            "kinkUtilization1": 50,
            "kinkUtilization2": 70,
            "kinkRate1": 1,
            "kinkRate2": 10,
            "maxRate25BPS": 225,
            "feeRatePercent": 20,
            "minFeeRate5BPS": 10,
            "maxFeeRate25BPS": 160
        },
    },
    'UNI': PrimeOnlyDefaults | {
        "address": "0xFa7F8980b0f1E64A2062791cc3b0871572f1F7f0",
        "name": "Uniswap",
        "decimals": 18,
        "baseOracle": ChainlinkOracles["UNI/USD"],
        "quoteOracle": ChainlinkOracles["ETH/USD"],
        "invertBase": False,
        "invertQuote": False,
        "pCashOracle": "0x46D2A413B066aE3A8d6E91BeA96872f541668689",
        "ethOracle": "0x394235A5BD3c90aD1c504b64329bCb2e06B7BaFe",

        "allowDebt": True,
        "buffer": 129,
        "haircut": 78,
        "liquidationDiscount": 108,
        "maxUnderlyingSupply": 120_000e8,

        "primeCashCurve": {
            "kinkUtilization1": 15,
            "kinkUtilization2": 70,
            "kinkRate1": 1,
            "kinkRate2": 3,
            "maxRate25BPS": 225,
            "feeRatePercent": 20,
            "minFeeRate5BPS": 10,
            "maxFeeRate25BPS": 160
        },
    },
    'LINK': PrimeOnlyDefaults | {
        "address": "0xf97f4df75117a78c1A5a0DBb814Af92458539FB4",
        "name": "ChainLink Token",
        "decimals": 18,
        "baseOracle": ChainlinkOracles["LINK/USD"],
        "quoteOracle": ChainlinkOracles["ETH/USD"],
        "invertBase": False,
        "invertQuote": False,
        "pCashOracle": "0x1EcE339C5e96B4EDDC14aebb86007346c9c22d2b",
        "ethOracle": "0x7283b4909127149EaDd229fae945f9E4911B69aE",

        "allowDebt": True,
        "buffer": 129,
        "haircut": 78,
        "liquidationDiscount": 108,
        "maxUnderlyingSupply": 45_000e8,

        "primeCashCurve": {
            "kinkUtilization1": 15,
            "kinkUtilization2": 70,
            "kinkRate1": 1,
            "kinkRate2": 3,
            "maxRate25BPS": 225,
            "feeRatePercent": 20,
            "minFeeRate5BPS": 10,
            "maxFeeRate25BPS": 160
        },
    },
    'LDO': PrimeOnlyDefaults | {
        "address": "0x13Ad51ed4F1B7e9Dc168d8a00cB3f4dDD85EfA60",
        "name": "Lido DAO Token",
        "decimals": 18,
        "baseOracle": ChainlinkOracles["LDO/USD"],
        "quoteOracle": ChainlinkOracles["ETH/USD"],
        "invertBase": False,
        "invertQuote": False,
        "pCashOracle": "0x8335E695C8d14cc7e93e8c4cf0a919D9cC8705a6",
        "ethOracle": "0x0fea5ea82add0efD3e197893dBFa40349E4B254f",

        "allowDebt": True,
        "buffer": 156,
        "haircut": 64,
        "liquidationDiscount": 109,
        "maxUnderlyingSupply": 55_000e8,

        "primeCashCurve": {
            "kinkUtilization1": 15,
            "kinkUtilization2": 70,
            "kinkRate1": 1,
            "kinkRate2": 3,
            "maxRate25BPS": 225,
            "feeRatePercent": 20,
            "minFeeRate5BPS": 10,
            "maxFeeRate25BPS": 160
        },
    },
    'tBTC': PrimeOnlyDefaults | {
        "currencyId": 16,
        "address": "0x6c84a8f1c29108F47a79964b5Fe888D4f4D0dE40",
        "name": "Arbitrum tBTC v2",
        "decimals": 18,
        "oracleType": "ChainlinkAdapter",
        "ethOracle": "0x97Cc93E87655D3d0F41aA0F54f86973fbd4B9Af7",
        "usdOracle": "",
        "pCashOracle": "0xc0F26a5E3528C87bdd74c18aa54E45455D593f35",

        # Prime Cash Curve
        "primeCashCurve": {
            "kinkUtilization1": 65,
            "kinkUtilization2": 70,
            "kinkRate1": 1,
            "kinkRate2": 4,
            "maxRate25BPS": 225,
            "feeRatePercent": 20,
            "minFeeRate5BPS": 10,
            "maxFeeRate25BPS": 160
        },

        "allowDebt": True,
        "buffer": 125,
        "haircut": 80,
        "liquidationDiscount": 106,
        "maxUnderlyingSupply": 0.10e8,
        "maxPrimeDebtUtilization": 80,
    }
}

ListedOrder = [
    # 1-4
    'ETH', 'DAI', 'USDC', 'WBTC',
    # 5-8
    'wstETH', 'FRAX', 'rETH', 'USDT',
    # 9-12
    'cbETH', 'GMX', 'ARB', 'RDNT',
    # 13-16
    'UNI', 'LINK', 'LDO', 'tBTC'
]