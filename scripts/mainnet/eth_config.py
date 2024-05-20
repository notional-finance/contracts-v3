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
    "wstETH/USD": "0x8770d8dEb4Bc923bf929cd260280B5F1dd69564D", # Notional Adapter
    "crvUSD/USD": "0xEEf0C605546958c1f899b6fB336C20671f9cD49F",
    "pyUSD/USD": "0x8f1dF6D7F2db73eECE86a18b4381F4707b918FB1",
    "GHO/USD": "0x3f12643D3f6f874d39C2a4c9f2Cd6f2DbAC877FC",
    "weETH/ETH": "0x5c9C449BbC9a6075A2c061dF312a35fd1E05fF22",
    "osETH/ETH": "0x66ac817f997Efd114EDFcccdce99F3268557B32C", # Redstone
    "osETH/USD": "0x3d3d7d124B0B80674730e0D31004790559209DEb",
    "ezETH/ETH": "0x636A000262F6aA9e1F094ABF0aD8f645C44f641C"
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
    "maxMintDeviation5BPS": 40,

    "rateOracleTimeWindow": 72,
    "allowDebt": True,
    "maxPrimeDebtUtilization": 80
}

PrimeOnlyDefaults = {
    "sequencerUptimeOracle": "0x0000000000000000000000000000000000000000",
    "primeRateOracleTimeWindow5Min": 72,
}

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
        "currencyId": 1,
        "address": ZERO_ADDRESS,
        "name": "Ether",
        "decimals": 18,
        "ethOracle": ZERO_ADDRESS,
        "usdOracle": ChainlinkOracles["ETH/USD"],

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
        "currencyId": 2,
        "address": "0x6B175474E89094C44Da98b954EedeAC495271d0F",
        "name": "Dai Stablecoin",
        "decimals": 18,
        "ethOracle": "0x6085b0a8f4c7ffa2e8ca578037792d6535d1e29b",
        "usdOracle": ChainlinkOracles["DAI/USD"],

        "buffer": 109,
        "haircut": 92,
        "liquidationDiscount": 104,
        "maxUnderlyingSupply": 10_000e8,
    },
    "USDC": CurrencyDefaults | Stablecoin_Curve | {
        "currencyId": 3,
        "address": "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48",
        "name": "USD Coin",
        "decimals": 6,
        "ethOracle": "0x68225f47813af66f186b3714ffe6a91850bc76b4",
        "usdOracle": ChainlinkOracles["USDC/USD"],

        "buffer": 109,
        "haircut": 92,
        "liquidationDiscount": 104,
        "maxUnderlyingSupply": 10_000e8,
    },
    "WBTC": PrimeOnlyDefaults | {
        "currencyId": 4,
        "address": "0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599",
        "name": "Wrapped BTC",
        "decimals": 8,
        # Wrapped BTC / BTC / ETH Oracle
        "ethOracle": "0xf9dd33af680d707efdec21332f249ae28cc13727",
        # Need to deploy WBTC / USD oracle
        "usdOracle": {
            "oracleType": "ChainlinkAdapter",
            "baseOracle": ChainlinkOracles["WBTC/BTC"],
            "quoteOracle": ChainlinkOracles["BTC/USD"],
            "invertBase": False,
            "invertQuote": True,
            "sequencerUptimeOracle": ZERO_ADDRESS
        },

        "buffer": 120,
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
            "maxRate25BPS": 225,
            "feeRatePercent": 20,
            "minFeeRate5BPS": 10,
            "maxFeeRate25BPS": 160
        },
    },
    "wstETH": CurrencyDefaults | LST_Curve | {
        "currencyId": 5,
        "address": "0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0",
        "name": "Wrapped Liquid Staked Ether",
        "decimals": 18,

        "oracleType": "wstETH",
        "baseOracle": ChainlinkOracles["stETH/ETH"],
        "invertBase": False,
        "invertQuote": False,
        "usdOracle": ChainlinkOracles["wstETH/USD"],

        "buffer": 120,
        "haircut": 83,
        "liquidationDiscount": 106,
        "maxUnderlyingSupply": 10e8,
    },
    "FRAX": CurrencyDefaults | Stablecoin_Curve | {
        "currencyId": 6,
        "address": "0x853d955aCEf822Db058eb8505911ED77F175b99e",
        "name": "Frax",
        "decimals": 18,
        "baseOracle": ChainlinkOracles["FRAX/USD"],
        "quoteOracle": ChainlinkOracles["ETH/USD"],
        "invertBase": False,
        "invertQuote": False,
        "usdOracle": ChainlinkOracles["FRAX/USD"],

        "buffer": 109,
        "haircut": 80,
        "liquidationDiscount": 104,
        "maxUnderlyingSupply": 10_000e8,
    },
    "rETH": CurrencyDefaults | LST_Curve | {
        "currencyId": 7,
        "address": "0xae78736Cd615f374D3085123A210448E74Fc6393",
        "name": "Rocket Pool ETH",
        "decimals": 18,
        "ethOracle": ChainlinkOracles["rETH/ETH"],
        "usdOracle": {
            "oracleType": "ChainlinkAdapter",
            "baseOracle": ChainlinkOracles["rETH/ETH"],
            "quoteOracle": ChainlinkOracles["ETH/USD"],
            "invertBase": False,
            "invertQuote": True,
            "sequencerUptimeOracle": ZERO_ADDRESS
        },

        "buffer": 120,
        "haircut": 83,
        "liquidationDiscount": 106,
        "maxUnderlyingSupply": 10e8,
    },
    "USDT": CurrencyDefaults | Stablecoin_Curve | {
        "currencyId": 8,
        "address": "0xdAC17F958D2ee523a2206206994597C13D831ec7",
        "name": "Tether USD",
        "decimals": 6,
        "baseOracle": ChainlinkOracles["USDT/USD"],
        "quoteOracle": ChainlinkOracles["ETH/USD"],
        "invertBase": False,
        "invertQuote": False,
        "usdOracle": ChainlinkOracles["USDT/USD"],

        "buffer": 109,
        "haircut": 85,
        "liquidationDiscount": 104,
        "maxUnderlyingSupply": 10_000e8,
    },
    'cbETH': CurrencyDefaults | LST_Curve | {
        "currencyId": 9,
        "address": "0xBe9895146f7AF43049ca1c1AE358B0541Ea49704",
        "name": "Coinbase Wrapped Staked ETH",
        "decimals": 18,
        "ethOracle": ChainlinkOracles["cbETH/ETH"],
        "usdOracle": "",

        "buffer": 120,
        "haircut": 83,
        "liquidationDiscount": 106,
        "maxUnderlyingSupply": 10e8,
    },
    'sDAI': PrimeOnlyDefaults | {
        "currencyId": 10,
        "address": "0x83F20F44975D03b1b09e64809B757c47f942BEeA",
        "name": "Savings Dai",
        "decimals": 18,
        "oracleType": "ERC4626",
        "baseOracle": ChainlinkOracles["ETH/DAI"],
        # This is the sDAI token address, it is used as its own oracle
        "quoteOracle": "0x83F20F44975D03b1b09e64809B757c47f942BEeA",
        "invertBase": False,
        "invertQuote": True,
        "usdOracle": "",

        # Prime Cash Curve
        "primeCashCurve": {
            "kinkUtilization1": 80,
            "kinkUtilization2": 85,
            "kinkRate1": 2,
            "kinkRate2": 8,
            "maxRate25BPS": 192,
            "feeRatePercent": 20,
            "minFeeRate5BPS": 10,
            "maxFeeRate25BPS": 160
        },

        "allowDebt": True,
        "buffer": 109,
        "haircut": 92,
        "liquidationDiscount": 105,
        "maxUnderlyingSupply": 10_000e8,
    },
    "GHO": CurrencyDefaults | {
        "currencyId": 11,
        "address": "0x40D16FC0246aD3160Ccc09B8D0D3A2cD28aE6C2f",
        "name": "Gho Token",
        "decimals": 18,
        "pCashOracle": "0x99745F4fE818d98bcEe35aBf3a2cFc80d42fC6AA",
        "ethOracle": "0x6Cce4Aa3fD019F967F824DF913dfF73328a8949b",
        "baseOracle": ChainlinkOracles["GHO/USD"],
        "quoteOracle": ChainlinkOracles["ETH/USD"],
        "invertBase": False,
        "invertQuote": False,
        "usdOracle": ChainlinkOracles["GHO/USD"],

        "buffer": 111,
        "haircut": 85,
        "liquidationDiscount": 105,
        "maxUnderlyingSupply": 2_000e8,

        "primeCashCurve": {
            "kinkUtilization1": 65,
            "kinkUtilization2": 85,
            "kinkRate1": 17,
            "kinkRate2": 51,
            "maxRate25BPS": 225,
            "feeRatePercent": 20,
            "minFeeRate5BPS": 10,
            "maxFeeRate25BPS": 160
        },
        "fCashCurves" : [{
            "kinkUtilization1": 20,
            "kinkUtilization2": 80,
            "kinkRate1": 35,
            "kinkRate2": 128,
            "maxRate25BPS": 152,
            "feeRatePercent": 8,
            "minFeeRate5BPS": 3,
            "maxFeeRate25BPS": 8
        }, {
            "kinkUtilization1": 20,
            "kinkUtilization2": 80,
            "kinkRate1": 35,
            "kinkRate2": 128,
            "maxRate25BPS": 152,
            "feeRatePercent": 8,
            "minFeeRate5BPS": 3,
            "maxFeeRate25BPS": 8
        }],
        "proportion": [0.35e9, 0.35e9],
        "depositShare": [0.6e8, 0.4e8],
        "leverageThreshold": [0.86e9, 0.86e9],
    },
}

ListedOrder = [
    # 1-4
    'ETH', 'DAI', 'USDC', 'WBTC',
    # 5-8
    'wstETH', 'FRAX', 'rETH', 'USDT',
    # 9-11
    'cbETH', 'sDAI', 'GHO'
]