import brownie
import pytest
from brownie.network import web3
from brownie.network.state import Chain
from scripts.config import GovernanceConfig
from scripts.deployment import TestEnvironment

chain = Chain()


@pytest.fixture(scope="module", autouse=True)
def environment(accounts):
    env = TestEnvironment(accounts[0], withGovernance=True, multisig=accounts[1])
    return env


@pytest.fixture(autouse=True)
def isolation(fn_isolation):
    pass


def test_note_token_initial_balances(environment, accounts):
    assert environment.noteERC20.balanceOf(environment.deployer.address) == 0
    assert (
        environment.noteERC20.balanceOf(environment.governor.address)
        == GovernanceConfig["initialBalances"]["DAO"]
    )
    assert (
        environment.noteERC20.balanceOf(environment.multisig.address)
        == GovernanceConfig["initialBalances"]["MULTISIG"]
    )
    assert (
        GovernanceConfig["initialBalances"]["DAO"] + GovernanceConfig["initialBalances"]["MULTISIG"]
        == environment.noteERC20.totalSupply()
    )


def test_note_token_cannot_reinitialize(environment, accounts):
    with brownie.reverts():
        environment.noteERC20.initialize(accounts[2].address, {"from": environment.deployer})

    with brownie.reverts():
        environment.noteERC20.initialize(accounts[2].address, {"from": accounts[2].address})


def test_note_token_transfer_to_reservoir_and_drip(environment, accounts, Reservoir):
    # TODO: where should this go?
    environment.noteERC20.delegate(environment.multisig, {"from": environment.multisig})

    reservoir = Reservoir.deploy(
        1e8,
        environment.noteERC20.address,
        environment.proxy.address,
        {"from": environment.deployer},
    )

    transferToReservoir = web3.eth.contract(abi=environment.noteERC20.abi).encodeABI(
        fn_name="transfer", args=[reservoir.address, int(1_000_000e8)]
    )

    targets = [environment.noteERC20.address]
    values = [0]
    calldatas = [transferToReservoir]

    # Values should not be listed here
    environment.governor.propose(targets, values, calldatas, {"from": environment.multisig})

    chain.mine(1)
    environment.governor.castVote(1, True, {"from": environment.multisig})
    chain.mine(GovernanceConfig["governorConfig"]["votingPeriodBlocks"])

    assert environment.governor.state(1) == 4  # success
    delay = environment.governor.getMinDelay()
    environment.governor.queueProposal(1, targets, values, calldatas, delay)
    chain.mine(1, timestamp=chain.time() + delay)
    environment.governor.executeProposal(1, targets, values, calldatas)

    assert environment.noteERC20.balanceOf(reservoir.address) == 1_000_000e8

    proxyBalanceBefore = environment.noteERC20.balanceOf(environment.proxy.address)
    blockTime = chain.time()
    reservoir.drip()
    proxyBalanceAfter = environment.noteERC20.balanceOf(environment.proxy.address)
    assert proxyBalanceAfter - proxyBalanceBefore == (blockTime - reservoir.DRIP_START()) * 1e8

    blockTime2 = chain.time()
    reservoir.drip()
    proxyBalanceAfterSecondDrip = environment.noteERC20.balanceOf(environment.proxy.address)
    assert proxyBalanceAfterSecondDrip - proxyBalanceAfter == (blockTime2 - blockTime) * 1e8


def test_note_token_reservoir_fails_on_zero(environment, accounts):
    pass


def test_upgrade_router_contract(environment, accounts):
    pass


def test_upgrade_governance_contract(environment, accounts):
    pass


def test_delegation(environment, accounts):
    pass
