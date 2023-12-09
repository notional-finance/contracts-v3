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