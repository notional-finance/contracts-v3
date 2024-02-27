from brownie import MigrateUSDC_AddressToCurrencyId, SecondaryRewarder, MockERC20
from brownie.network import Chain
from scripts.inspect import get_addresses

chain = Chain()

MIGRATE_USDC = MigrateUSDC_AddressToCurrencyId.at('0xbaA748fc864Ece66Fd958027F1A07b346C2aB387')
FINAL_ROUTER = '0x8560C22F3B1FB258741d93520F62288a7AAE93c8'
# This is nUSDT
REWARDER = SecondaryRewarder.at('0xe670942CE88d0ac8E655d30E5EF0229e969de26C')

nUSDTHolders = [
    "0x0826fd0aba8cb277bb1d55f971dff72e69bd92ba",
    "0x12924049e2d21664e35387c69429c98e9891a820",
    "0x139f2916cf105a494efa59645bdc0598a5d4c256",
    "0x140daad3f2ddf2cce32436ca6265c4bbd1ccef92",
    "0x14bd2fa02e701ede251bf2bf4fc8bc5603e4afb1",
    "0x1dcf476bc4f86b8f49e044f3c09d45cdd05894c8",
    "0x268766bd81e082b0a8e671fa950525f57b096b3b",
    "0x315475a886805803a62f6c5e1390eaa8ca752e48",
    "0x34f099c29c45ee4ae55bc219e019dc1136431995",
    "0x35e4535b8fb48eb815429104d74b3792d0e730db",
    "0x3a8c7a77a69005d81ee26d85c49de73bf003c901",
    "0x3e6d1471b6f22fe03b05dfa81dec5b08e69838f2",
    "0x3f268ecd9a18997eb8b177ae5737d042ee660334",
    "0x4a07a7c6fe412d14134dce2bb738b32757b968fe",
    "0x5ac342c4ae3d656193a2bb9a683fde9777c94ba2",
    "0x5bcb86339f2b53ca52edadc4c692199a78f06e71",
    "0x6cfa99b2352163d70bd52de24cdbf553374b9335",
    "0x6e22706d6e86c38f4bad40415b1b4c76f5b821b0",
    "0x6edeadb79979288c3916eb972ed233d8053d3d4c",
    "0x7292667c8a55bd56d496d2edcb5cfb37d554f943",
    "0x81278d88f60bed5e5d01256d44e571e06e1eeb3b",
    "0x8a2ef2e1ae7dbaa224bcbd6d84b95f4c071f1cf7",
    "0x940d92f24547a87ea4fd59d5c78a842bee41bb57",
    "0x94570e4e3e204bb40b66838239c0b5c03089aa96",
    "0x9f754a408be97c2f001a3a12a6a966c6d109761f",
    "0xa03f2709f2641e8fc08ff256a84268620c15a72c",
    "0xa2e5b6b59223bc966a14e61781cce07d2b22fe03",
    "0xa42fc4ca35dbe3c9c529c6509445fe7664e22bb9",
    "0xbe2174ff12a71b6deeca5b9aaf4c2931e8c62ae5",
    "0xbf778fc19d0b55575711b6339a3680d07352b221",
    "0xc0a7f07b2a61d6017a32812aa91c2747b971d478",
    "0xc34ae1a39662415a4720d4a3e7c2be0e202568c2",
    "0xc5dfbcf2461c0edc8d0f98d8b0ed9b9fc8b86af9",
    "0xcbaafd37d054c33c1abb0213a7a812161eee8255",
    "0xd0891dbc850e1c9f32aa1729d1a2933784aa7db4",
    "0xd37f7b32a541d9e423f759dff1dd63181651bd04",
    "0xd74e7325dfab7d7d1ecbf22e6e6874061c50f243",
    "0xd83d994b102a5e6b452469d26fe5acd1608954f9",
    "0xdd83eaa1a66369ab09b2642a1a130287c4ad8e40",
    "0xe0735afbfa516e199cf6aff16965cafc2dc22e66",
    "0xebf98b683002f278060aa9d0ab01ff66c6590e7b",
    "0xf04c4b23fcc37c6861927f75d44c90cd1e461ee6",
    "0xfcc06f7f02f6ab02051f259db4f82f20d8d02112",
    "0xfe67d1249e2555a051069ce6cd46021b7fd63f82",
    "0xff5df32fc2ad0421662109f6998fdf7db30944a7",
    "0xff79cd75bae6f7c355385b0976a0b2426d3fa457"
]

def main():
    (_, notional, *_) = get_addresses()
    
    # Assert USDC is broken
    assert notional.getCurrencyId("0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8") == 3

    # Call migrate usdc PatchFix
    notional.transferOwnership(MIGRATE_USDC, False, {"from": notional.owner()})
    MIGRATE_USDC.atomicPatchAndUpgrade({"from": notional.owner()})

    # Assert that USDC is fixed
    assert notional.getCurrencyId("0xaf88d065e77c8cC2239327C5EDb3A432268e5831") == 3

    # Should also update nToken settings
    notional.upgradeTo(FINAL_ROUTER, {"from": notional.owner()})
    for id in range(1, 10):
        # Set all the token parameters to 5 minutes
        notional.updateTokenCollateralParameters(
            id, 20, 90, 24, 20, 98, 5, {"from": notional.owner()}
        )

    # Set rewarder for USDT for one week (we use 360 day years)
    REWARDER.setIncentiveEmissionRate(51.4e8, chain.time() + 86400 * 7, {"from": notional.owner()})
    notional.setSecondaryIncentiveRewarder(8, REWARDER,
        {"from": notional.owner()}
    )

    # Ensure we can settle these vault accounts
    notional.settleVaultAccount(
        '0xe31ac8c8c5b2f51abe13ef3afd3e2a552c1165b2', '0xdb08f663e5d765949054785f2ed1b2aa1e9c22cf',
        {"from": notional.owner()}
    )
    notional.settleVaultAccount(
        '0xf5c4e22e63F1eb3451cBE41Bd906229DCf9dba15', '0x8ae7a8789a81a43566d0ee70264252c0db826940',
        {"from": notional.owner()}
    )

    test_secondary_rewarder(notional)


def test_secondary_rewarder(notional):
    # Test Secondary Rewarder
    nUSDTHolder = '0xd74e7325dFab7D7D1ecbf22e6E6874061C50f243'
    chain.mine(1, timedelta=43200)
    arb = MockERC20.at(REWARDER.REWARD_TOKEN())
    nUSDT = MockERC20.at(REWARDER.NTOKEN_ADDRESS())
    arb.transfer(REWARDER, 1.01e18, {"from": "0xf3fc178157fb3c87548baa86f9d24ba38e649b58"})

    arbIncentives = REWARDER.getAccountRewardClaim(nUSDTHolder, chain.time())
    balanceBefore = arb.balanceOf(nUSDTHolder)
    notional.nTokenClaimIncentives({'from': nUSDTHolder})
    balanceAfter = arb.balanceOf(nUSDTHolder)

    assert (balanceAfter - balanceBefore) / arbIncentives < 1.001

    endTime = REWARDER.endTime()
    chain.mine(1, timestamp=endTime)

    arbIncentives = REWARDER.getAccountRewardClaim(nUSDTHolder, chain.time())
    balanceBefore = arb.balanceOf(nUSDTHolder)
    notional.nTokenClaimIncentives({'from': nUSDTHolder})
    balanceAfter = arb.balanceOf(nUSDTHolder)

    assert (balanceAfter - balanceBefore) / arbIncentives < 1.001

    chain.mine(1, timedelta=86400)
    assert REWARDER.getAccountRewardClaim(nUSDTHolder, chain.time()) == 0

    # Ensure everyone can claim their ARB incentives
    for h in nUSDTHolders:
        arbIncentives = REWARDER.getAccountRewardClaim(h, chain.time() + 1)
        balance = nUSDT.balanceOf(h)
        print(h, arbIncentives / 1e18, balance / 1e8)
        notional.nTokenClaimIncentives({'from': h})

    assert arb.balanceOf(REWARDER) < 0.05e18