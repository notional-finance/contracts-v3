from brownie import ZERO_ADDRESS

ChainlinkOracles = {
    "ETH/USD": "0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419",
    "USDC/USD": "0x8fFfFfd4AfB6115b954Bd326cbe7B4BA576818f6",
    "DAI/USD": "0xAed0c38402a5d19df6E4c03F4E2DceD6e29c1ee9",
    "WBTC/BTC": "0xfdFD9C85aD200c506Cf9e21F1FD8dd01932FBB23",
    "BTC/USD": "0xF4030086522a5bEEa4988F8cA5B36dbC97BeE88c",
    "FRAX/USD": "0xB9E1E3A9feFf48998E45Fa90847ed4D467E8BcfD",
    "stETH/ETH": "0x86392dC19c0b719886221c78AB11eb8Cf5c52812",
    "stETH/USD": "0xCfE54B5cD566aB89272946F602D76Ea879CAb4a8",
    "rETH/ETH": "0x536218f9E9Eb48863970252233c8F271f554C2d0",
    "USDT/USD": "0x3E7d1eAB13ad0104d2750B8863b489D65364e32D",
    "cbETH/ETH": "0xF017fcB346A1885194689bA23Eff2fE6fA5C483b",
    "ETH/DAI": "0x6085b0a8f4c7ffa2e8ca578037792d6535d1e29b", # Existing Chainlink Adapter
    "wstETH/stETH": "", # TODO: need to call contract directly
    "sDAI/DAI": "", # TODO: need to call contract direclty
}

CurrencyDefaults = {
    "sequencerUptimeOracle": "0x0000000000000000000000000000000000000000",

    # Cash Group
    "maxMarketIndex": 2,
    "primeRateOracleTimeWindow5Min": 72,
    "reserveFeeShare": 80,
    "fCashHaircut": 22,
    "debtBuffer": 22,
    "liquidationfCashDiscount": 6,
    "liquidationDebtBuffer": 6,
    "minOracleRate": 20,
    "maxOracleRate": 28,
    "maxDiscountFactor": 40,

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
    "sequencerUptimeOracle": "0x0000000000000000000000000000000000000000",
    "primeRateOracleTimeWindow5Min": 72,
}

LST_fCash = [{
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
}]

LST_Curve = {
    "primeCashCurve": {
        "kinkUtilization1": 70,
        "kinkUtilization2": 75,
        "kinkRate1": 2,
        "kinkRate2": 5,
        "maxRate25BPS": 225,
        "feeRatePercent": 20,
        "minFeeRate5BPS": 10,
        "maxFeeRate25BPS": 160
    },
    "fCashCurves" : [{
        "kinkUtilization1": 60,
        "kinkUtilization2": 80,
        "kinkRate1": 9,
        "kinkRate2": 34,
        "maxRate25BPS": 120,
        "feeRatePercent": 8,
        "minFeeRate5BPS": 3,
        "maxFeeRate25BPS": 8
    }, {
        "kinkUtilization1": 60,
        "kinkUtilization2": 80,
        "kinkRate1": 10,
        "kinkRate2": 41,
        "maxRate25BPS": 100,
        "feeRatePercent": 8,
        "minFeeRate5BPS": 3,
        "maxFeeRate25BPS": 8
    }],
    "proportion": [0.3e9, 0.3e9],
    "depositShare": [0.6e8, 0.4e8],
    "leverageThreshold": [0.84e9, 0.84e9],
}

Stablecoin_Curve = {
    "primeCashCurve": {
        "kinkUtilization1": 80,
        "kinkUtilization2": 85,
        "kinkRate1": 10,
        "kinkRate2": 25,
        "maxRate25BPS": 192,
        "feeRatePercent": 20,
        "minFeeRate5BPS": 10,
        "maxFeeRate25BPS": 160
    },
    "fCashCurves" : [{
        "kinkUtilization1": 60,
        "kinkUtilization2": 80,
        "kinkRate1": 39,
        "kinkRate2": 73,
        "maxRate25BPS": 120,
        "feeRatePercent": 8,
        "minFeeRate5BPS": 3,
        "maxFeeRate25BPS": 8
    }, {
        "kinkUtilization1": 60,
        "kinkUtilization2": 80,
        "kinkRate1": 46,
        "kinkRate2": 82,
        "maxRate25BPS": 100,
        "feeRatePercent": 8,
        "minFeeRate5BPS": 3,
        "maxFeeRate25BPS": 8
    }],
    "proportion": [0.3e9, 0.3e9],
    "depositShare": [0.6e8, 0.4e8],
    "leverageThreshold": [0.84e9, 0.84e9],
}
 
ListedTokens = {
    "ETH": CurrencyDefaults | {
        "address": ZERO_ADDRESS,
        "name": "Ether",
        "decimals": 18,

        "buffer": 120,
        "haircut": 87,
        "liquidationDiscount": 105,
        "maxUnderlyingSupply": 10e8,

        # Prime Cash Curve
        "primeCashCurve": {
            "kinkUtilization1": 75,
            "kinkUtilization2": 80,
            "kinkRate1": 5,
            "kinkRate2": 12,
            "maxRate25BPS": 255,
            "feeRatePercent": 20,
            "minFeeRate5BPS": 10,
            "maxFeeRate25BPS": 160
        },

        # fCash Curve
        "fCashCurves" : [{
            "kinkUtilization1": 55,
            "kinkUtilization2": 80,
            "kinkRate1": 34,
            "kinkRate2": 85,
            "maxRate25BPS": 120,
            "feeRatePercent": 8,
            "minFeeRate5BPS": 3,
            "maxFeeRate25BPS": 8
        }, {
            "kinkUtilization1": 55,
            "kinkUtilization2": 80,
            "kinkRate1": 34,
            "kinkRate2": 85,
            "maxRate25BPS": 120,
            "feeRatePercent": 8,
            "minFeeRate5BPS": 3,
            "maxFeeRate25BPS": 8
        }],

        "proportion": [0.3e9, 0.3e9],
        "depositShare": [0.6e8, 0.4e8],
        "leverageThreshold": [0.84e9, 0.84e9],
    },
    "DAI": CurrencyDefaults | Stablecoin_Curve | {
        "address": "0x6B175474E89094C44Da98b954EedeAC495271d0F",
        "name": "Dai Stablecoin",
        "decimals": 18,
        "ethOracle": "0x6085b0a8f4c7ffa2e8ca578037792d6535d1e29b",

        "buffer": 109,
        "haircut": 92,
        "liquidationDiscount": 104,
        "maxUnderlyingSupply": 10_000e8,
    },
    "USDC": CurrencyDefaults | Stablecoin_Curve | {
        "address": "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48",
        "name": "USD Coin",
        "decimals": 6,
        "ethOracle": "0x68225f47813af66f186b3714ffe6a91850bc76b4",

        "buffer": 109,
        "haircut": 92,
        "liquidationDiscount": 104,
        "maxUnderlyingSupply": 10_000e8,
    },
    "WBTC": PrimeOnlyDefaults | {
        "address": "0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599",
        "name": "Wrapped BTC",
        "decimals": 8,
        # Wrapped BTC / BTC / ETH Oracle
        "ethOracle": "0xf9dd33af680d707efdec21332f249ae28cc13727",

        "buffer": 124,
        "haircut": 84,
        "liquidationDiscount": 105,
        "maxUnderlyingSupply": 1e8,

        "allowDebt": True,
        # Prime Cash Curve
        "primeCashCurve": {
            "kinkUtilization1": 65,
            "kinkUtilization2": 70,
            "kinkRate1": 3,
            "kinkRate2": 6,
            "maxRate25BPS": 255,
            "feeRatePercent": 20,
            "minFeeRate5BPS": 10,
            "maxFeeRate25BPS": 160
        },
    },
    "wstETH": CurrencyDefaults | LST_Curve | {
        "address": "0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0",
        "name": "Wrapped Liquid Staked Ether",
        "decimals": 18,

        "baseOracle": ChainlinkOracles["stETH/wstETH"],
        "quoteOracle": ChainlinkOracles["stETH/ETH"],
        "invertBase": False,
        "invertQuote": False,

        "buffer": 120,
        "haircut": 83,
        "liquidationDiscount": 106,
        "maxUnderlyingSupply": 10e8,
    },
    "FRAX": CurrencyDefaults | Stablecoin_Curve | {
        "address": "0x853d955aCEf822Db058eb8505911ED77F175b99e",
        "name": "Frax",
        "decimals": 18,
        "baseOracle": ChainlinkOracles["FRAX/USD"],
        "quoteOracle": ChainlinkOracles["ETH/USD"],
        "invertBase": False,
        "invertQuote": False,

        "buffer": 109,
        "haircut": 80,
        "liquidationDiscount": 104,
        "maxUnderlyingSupply": 10_000e8,
    },
    "rETH": CurrencyDefaults | LST_Curve | {
        "address": "0xae78736Cd615f374D3085123A210448E74Fc6393",
        "name": "Rocket Pool ETH",
        "decimals": 18,
        "ethOracle": ChainlinkOracles["rETH/ETH"],

        "buffer": 120,
        "haircut": 83,
        "liquidationDiscount": 106,
        "maxUnderlyingSupply": 10e8,
    },
    "USDT": CurrencyDefaults | Stablecoin_Curve | {
        "address": "0xdAC17F958D2ee523a2206206994597C13D831ec7",
        "name": "Tether USD",
        "decimals": 6,
        "baseOracle": ChainlinkOracles["USDT/USD"],
        "quoteOracle": ChainlinkOracles["ETH/USD"],
        "invertBase": False,
        "invertQuote": False,

        "buffer": 109,
        "haircut": 85,
        "liquidationDiscount": 104,
        "maxUnderlyingSupply": 10_000e8,
    },
    'cbETH': CurrencyDefaults | LST_Curve | {
        "address": "0xBe9895146f7AF43049ca1c1AE358B0541Ea49704",
        "name": "Coinbase Wrapped Staked ETH",
        "decimals": 18,
        "ethOracle": ChainlinkOracles["cbETH/ETH"],

        "buffer": 120,
        "haircut": 83,
        "liquidationDiscount": 106,
        "maxUnderlyingSupply": 10e8,
    },
    'sDAI': PrimeOnlyDefaults | {
        "address": "0x83F20F44975D03b1b09e64809B757c47f942BEeA",
        "name": "sDAI",
        "decimals": 18,
        "baseOracle": ChainlinkOracles["ETH/DAI"],
        "quoteOracle": ChainlinkOracles["sDAI/DAI"],
        "invertBase": True,
        "invertQuote": False,

        "allowDebt": True,
        "buffer": 109,
        "haircut": 92,
        "liquidationDiscount": 105,
        "maxUnderlyingSupply": 10_000e8,
    }
}

ListedOrder = [
    # 1-4
    'ETH', 'DAI', 'USDC', 'WBTC',
    # 5-8
    'wstETH', 'FRAX', 'rETH', 'USDT',
    # 9-10
    'cbETH', 'sDAI'
]