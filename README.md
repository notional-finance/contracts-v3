# Notional Contracts V3

Notional V3 is an upgrade to Notional V2 that enables variable rate lending on top of existing fixed rate lending functionality. Notional V3 also improves the Notional Leveraged Vault framework, allowing both variable and fixed rate leverage. The introduction of variable rate lending removes many impediments to fixed rate adoption, primarily around settlement. In Notional V3, fixed rates now settle to variable rates instead of having a hard, discrete cash settlement requirement. Variable rate markets also improve returns to the nToken liquidity providers. Variable rates also allow for temporarily illiquid fCash to be liquidated by forcing the account to borrow at a variable rate (effectively forcing an interest rate swap), greatly reducing the risk of illiquid fCash liquidations.

These changes greatly improve the economic security of Notional V3.

## Deployments

Most Notional transactions (lending, borrowing, providing liquidity) go through the main Notional proxy. Currently, Notional is only deployed on Ethereum Mainnet, Kovan testnet and Goerli testnet. Contract addresses can be found [here](https://docs.notional.finance/developer-documentation/#deployed-contract-addresses)

Notional is undergoing a process of gradual decentralization. Due to the complexity of the system, the creators of the protocol feel that it is necessary to be able to respond quickly in case of issues during the initial launch of the system. Because many economic conditions in Notional only arise at specific periods (i.e. during initialize markets every three months), the period of administrative control may last longer than other DeFi protocols.

Currently Notional is owned by a three of five Gnosis multisig contract where two signers are the founders of the protocol (Jeff and Teddy) and the three other signers are community members. A longer discussion of administrative controls can be found [here](https://docs.notional.finance/developer-documentation/on-chain/notional-governance-reference)

## Codebase

A full protocol description can be found at the [docs](https://docs.notional.finance/notional-v3/)

- Videos: https://www.youtube.com/watch?v=-8a5kY0QeYY&list=PLnKdM8f8QEJ2lJ59ZjhVCcJvrT056X0Ga
- Blogs: https://blog.notional.finance/tag/deep-dive/

The codebase is broken down into the following modules, each directory has a `_README.md` file that describes the module.

## Running Tests

The script: `bin/runTests.sh` will run all the tests against the repository. The current tests use both foundry and brownie. We are in a slow process of transitioning testing from brownie to foundry.

### Brownie

To run brownie tests, you can set up an environment using the `bin/setup.sh` script. There are a few gotchas:

You may run into issues importing the `ContractsV3Project`. This is because the folder the repo is cloned into must equal `contracts-v3`, this is how Brownie determines the project name.

You may run into a compilation error on IERC20.sol package in the OpenZeppelin Contracts 3.4.2-solc-0.7 dependency. Change the pragma in that file from:

`pragma solidity ^0.7.0`

to

`pragma solidity >=0.7.0`

You may run into a `brownie.exceptions.RPCRequestError: Method evm_setAccountNonce not supported` error. You will need to use Ganache instead of Hardhat or Anvil as your test execution environment. To change this you will need to update your `~/.brownie/network-config.yaml` file to include the following network:

```
- cmd: npx ganache
  cmd_settings:
    accounts: 10
    evm_version: istanbul
    gas_limit: 12000000
    mnemonic: brownie
    port: 8545
  host: http://127.0.0.1
  id: development
  name: Ganache7
```

When using Ganache, you may see an error like this:

```
INTERNALERROR>   File "contracts-v3/venv/lib/python3.10/site-packages/brownie/network/rpc/ganache.py", line 115, in get_ganache_version
INTERNALERROR>     raise ValueError("could not read ganache version: {}".format(ganache_version_stdout))
INTERNALERROR> ValueError: could not read ganache version: b'8.19.3\n'
```

This is because brownie has an incorrect version regex for ganache. You must edit this python file: `venv/lib/python3.10/site-packages/brownie/network/rpc/ganache.py` and update the `ganache_version_match` line in the function:

```
def get_ganache_version(ganache_executable: str) -> int:
    ganache_version_proc = psutil.Popen([ganache_executable, "--version"], stdout=PIPE)
    ganache_version_stdout, _ = ganache_version_proc.communicate()
    # Change this version match line and remove the "v"
    # ganache_version_match = re.search(r"(v[0-9]+)\.", ganache_version_stdout.decode())
    ganache_version_match = re.search(r"([0-9]+)\.", ganache_version_stdout.decode())
    if not ganache_version_match:
        raise ValueError("could not read ganache version: {}".format(ganache_version_stdout))
    return int(ganache_version_match.group(1))
```

There are a lot of tests and it make take awhile (it takes a few hours on my M2 Apple Silicon). You can run individual test files via brownie test [path] or add the decorator @pytest.mark.only to a function and run a file using brownie test [path] -m only

### Foundry

Foundry tests require an `.env` file with the following variable set:

```
ARBITRUM_RPC_URL=<RPC URL>
```

Foundry tests may fail on an error: [FAIL. Reason: setup failed: revert: NOTE] setUp()

This is because Foundry tests are run against an Arbitrum fork environment and require the `Deployments.sol` file to be updated with Arbitrum addresses. The `bin/runTests.sh` file has a line to apply a patch to this file so that it will work properly:

`git apply bin/arb.patch`