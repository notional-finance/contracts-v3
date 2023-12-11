// SPDX-License-Identifier: GPL-3.0-only
pragma solidity =0.7.6;

import {GenericToken} from "../../internal/balances/protocols/GenericToken.sol";
import {IRewarder} from "../../../interfaces/notional/IRewarder.sol";
import {NotionalProxy} from "../../../interfaces/notional/NotionalProxy.sol";
import {IERC20} from "../../../interfaces/IERC20.sol";
import {Constants} from "../../global/Constants.sol";
import {SafeInt256} from "../../math/SafeInt256.sol";
import {SafeUint256} from "../../math/SafeUint256.sol";
import {MerkleProof} from "@openzeppelin/contracts/cryptography/MerkleProof.sol";

contract SecondaryRewarder is IRewarder {
    using SafeUint256 for uint256;
    using SafeInt256 for int256;

    NotionalProxy public immutable NOTIONAL;
    address public immutable NTOKEN_ADDRESS;
    address public immutable REWARD_TOKEN;
    uint8 public immutable REWARD_TOKEN_DECIMALS;
    uint16 public immutable override CURRENCY_ID;

    /// @notice When a rewarder is detached, it converts to an airdrop contract using the
    /// this merkleRoot that is set.
    /// @dev Uses a single storage slot
    bytes32 public merkleRoot;

    /* Rest of storage variables are packed into 232 bits (29 bytes, 3 left unused) */
    /// @notice When true user needs to call contract directly to claim any rewards left
    bool public override detached;
    /// @notice Marks the timestamp when incentives will end. Will always be less than block.timestamp
    /// if detached is true.
    uint32 public endTime;

    /// @notice The emission rate of REWARD_TOKEN in WHOLE token precision (i.e. token value without
    /// any decimals).
    uint32 public override emissionRatePerYear;

    /// @notice Last time the contract accumulated the reward
    uint32 public override lastAccumulatedTime;

    /// @notice Aggregate tokens accumulated per nToken at `lastAccumulateTime`
    uint128 public override accumulatedRewardPerNToken;

    /// @notice Reward debt per account stored in 18 decimals.
    mapping(address => uint128) public rewardDebtPerAccount;

    modifier onlyOwner() {
        require(msg.sender == NOTIONAL.owner(), "Only owner");
        _;
    }

    modifier onlyNotional() {
        require(msg.sender == address(NOTIONAL), "Only Notional");
        _;
    }

    constructor(
        NotionalProxy notional,
        uint16 currencyId,
        IERC20 incentive_token,
        uint32 _emissionRatePerYear,
        uint32 _endTime
    ) {
        NOTIONAL = notional;
        CURRENCY_ID = currencyId;
        NTOKEN_ADDRESS = notional.nTokenAddress(currencyId);
        REWARD_TOKEN = address(incentive_token);
        REWARD_TOKEN_DECIMALS = IERC20(address(incentive_token)).decimals();

        emissionRatePerYear = _emissionRatePerYear;
        lastAccumulatedTime = uint32(block.timestamp);
        endTime = _endTime;
    }

    /// @notice Get amount of reward account can claim at specified block time, only called before rewarder is detached
    /// @param account address to get reward amount for
    /// @param blockTime block time at which to get reward amount
    function getAccountRewardClaim(address account, uint32 blockTime)
        external
        override
        returns (uint256 rewardToClaim)
    {
        require(!detached, "Detached");
        require(lastAccumulatedTime <= blockTime, "Invalid block time");

        uint256 totalSupply = IERC20(NTOKEN_ADDRESS).totalSupply();
        uint256 nTokenBalance = IERC20(NTOKEN_ADDRESS).balanceOf(account);

        _accumulateRewardPerNToken(blockTime, totalSupply);
        rewardToClaim = _calculateRewardToClaim(account, nTokenBalance);
    }

    /// @notice Get amount of reward still left for account to claim, only called after rewarder is detached
    /// and merkle root is set
    /// @param account address to get reward amount for
    /// @param nTokenBalanceAtDetach nToken balance of account at time of detachment
    /// @param proof merkle proof to prove account and nTokenBalanceAtDetach are in tree
    function getAccountRewardClaim(address account, uint256 nTokenBalanceAtDetach, bytes32[] calldata proof)
        external
        view
        override
        returns (uint256 rewardToClaim)
    {
        require(detached && merkleRoot != bytes32(0), "Not detached");

        _checkProof(account, nTokenBalanceAtDetach, proof);
        // no need to accumulate, it was already accumulated when rewarder was detached
        rewardToClaim = _calculateRewardToClaim(account, nTokenBalanceAtDetach);
    }

    /// @notice Set incentive emission rate and incentive period end time, called only in case emission
    /// rate or incentive period changes since it is already set at deploy time, only can be called before
    /// rewarder is detached
    /// @param _emissionRatePerYear emission rate per year in WHOLE token precision
    /// @param _endTime time in seconds when incentive period will end
    function setIncentiveEmissionRate(uint32 _emissionRatePerYear, uint32 _endTime) external onlyOwner {
        require(!detached, "Detached");
        uint256 totalSupply = IERC20(NTOKEN_ADDRESS).totalSupply();

        _accumulateRewardPerNToken(uint32(block.timestamp), totalSupply);

        emissionRatePerYear = _emissionRatePerYear;
        endTime = _endTime;
    }

    /// @notice Set merkle root, only called after rewarder is detached
    /// @param _merkleRoot merkle root of the tree that contains accounts and nToken balances at detach time
    function setMerkleRoot(bytes32 _merkleRoot) external onlyOwner {
        require(_merkleRoot != bytes32(0), "Invalid");
        merkleRoot = _merkleRoot;
    }

    /// @notice Allows owner to recover any ERC20 or ETH mistakenly sent to this contract
    /// @param token address of the token to recover, in case of ETH pass address(0)
    /// @param amount amount to recover
    function recover(address token, uint256 amount) external onlyOwner {
        if (Constants.ETH_ADDRESS == token) {
            (bool status,) = msg.sender.call{value: amount}("");
            require(status);
        } else {
            IERC20(token).transfer(msg.sender, amount);
        }
    }

    /// @dev Called from Notional system to detach rewarder when switching to a new rewarder or when incentive
    /// period is over, after this merkle tree of user nToken balances at detach time should be generated
    /// offline and merkle root uploaded to this contract
    function detach() external override onlyNotional {
        require(!detached, "Already detached");

        // accumulate for the last time if needed
        uint256 totalSupply = IERC20(NTOKEN_ADDRESS).totalSupply();
        _accumulateRewardPerNToken(uint32(block.timestamp), totalSupply);

        detached = true;
        emissionRatePerYear = 0;

        if (block.timestamp < endTime) {
            endTime = uint32(block.timestamp);
        }
    }

    /// @notice Allows claiming rewards after rewarder has been detached
    /// @param account address to claim rewards for
    /// @param nTokenBalanceAtDetach nToken balance of account at time of detachment
    /// @param proof merkle proof to prove account and nTokenBalanceAtDetach are in tree
    function claimRewardsDirect(address account, uint256 nTokenBalanceAtDetach, bytes32[] calldata proof)
        external
        override
    {
        require(detached, "Not detached");

        _checkProof(account, nTokenBalanceAtDetach, proof);

        _claimRewards(account, nTokenBalanceAtDetach, nTokenBalanceAtDetach);
    }

    /// @notice Allows claiming rewards but only from Notional system, called on each nToken balance change
    /// @param account address to claim rewards for
    /// @param currencyId id number of the currency
    /// @param nTokenBalanceBefore account nToken balance before the change
    /// @param nTokenBalanceAfter account nToken balance after the change
    /// @param priorNTokenSupply total nToken supply before the change
    function claimRewards(
        address account,
        uint16 currencyId,
        uint256 nTokenBalanceBefore,
        uint256 nTokenBalanceAfter,
        uint256 priorNTokenSupply
    ) external override onlyNotional {
        require(!detached, "Detached");
        require(currencyId == CURRENCY_ID, "Wrong currency id");

        _accumulateRewardPerNToken(uint32(block.timestamp), priorNTokenSupply);
        _claimRewards(account, nTokenBalanceBefore, nTokenBalanceAfter);
    }

    function _claimRewards(address account, uint256 nTokenBalanceBefore, uint256 nTokenBalanceAfter) private {
        uint256 rewardToClaim = _calculateRewardToClaim(account, nTokenBalanceBefore);

        // Precision here is:
        //  nTokenBalanceAfter (INTERNAL_TOKEN_PRECISION)
        //  accumulatedRewardPerNToken (INCENTIVE_ACCUMULATION_PRECISION - INTERNAL_TOKEN_PRECISION)
        //  => INCENTIVE_ACCUMULATION_PRECISION (1e18)
        // forgefmt: disable-next-item
        rewardDebtPerAccount[account] = nTokenBalanceAfter
            .mul(accumulatedRewardPerNToken)
            .toUint128();

        if (0 < rewardToClaim) {
            GenericToken.safeTransferOut(REWARD_TOKEN, account, rewardToClaim);
            emit RewardTransfer(REWARD_TOKEN, account, rewardToClaim);
        }
    }

    function _accumulateRewardPerNToken(uint32 blockTime, uint256 totalSupply) private {
        uint32 time = uint32(SafeInt256.min(blockTime, endTime));

        if (lastAccumulatedTime < time && 0 < totalSupply) {
            // NOTE: no underflow, checked in if statement
            uint256 timeSinceLastAccumulation = time - lastAccumulatedTime;
            // Precision here is:
            //  timeSinceLastAccumulation (SECONDS)
            //  INCENTIVE_ACCUMULATION_PRECISION (1e18)
            //  WHOLE_TOKENS (?)
            // DIVIDE BY
            //  YEAR (SECONDS)
            //  INTERNAL_TOKEN_PRECISION
            // => Precision = 10 ** (INCENTIVE_ACCUMULATION_PRECISION - INTERNAL_TOKEN_PRECISION)
            // => 1e10

            // forgefmt: disable-next-item
            uint256 additionalIncentiveAccumulatedPerNToken = timeSinceLastAccumulation
                .mul(Constants.INCENTIVE_ACCUMULATION_PRECISION)
                .mul(emissionRatePerYear)
                .div(Constants.YEAR)
                .div(totalSupply);

            accumulatedRewardPerNToken =
                uint256(accumulatedRewardPerNToken).add(additionalIncentiveAccumulatedPerNToken).toUint128();
        }
        lastAccumulatedTime = uint32(block.timestamp);
    }

    function _calculateRewardToClaim(address account, uint256 nTokenBalanceAtLastClaim)
        private
        view
        returns (uint256)
    {
        // Precision here is:
        //   nTokenBalanceAtLastClaim (INTERNAL_TOKEN_PRECISION)
        //   accumulatedRewardPerNToken (INCENTIVE_ACCUMULATION_PRECISION - INTERNAL_TOKEN_PRECISION)
        // => INCENTIVE_ACCUMULATION_PRECISION
        // SUB rewardDebtPerAccount (INCENTIVE_ACCUMULATION_PRECISION)
        //
        // - div INCENTIVE_ACCUMULATION_PRECISION
        // - mul REWARD_TOKEN_DECIMALS
        // => REWARD_TOKEN_DECIMALS

        // forgefmt: disable-next-item
        return uint256(nTokenBalanceAtLastClaim)
            .mul(accumulatedRewardPerNToken)
            .sub(rewardDebtPerAccount[account])
            .div(Constants.INCENTIVE_ACCUMULATION_PRECISION)
            .mul(10 ** REWARD_TOKEN_DECIMALS);
    }

    /// @notice Verify merkle proof, or revert if not in tree
    function _checkProof(address account, uint256 balance, bytes32[] calldata proof) private view {
        // Verify merkle proof, or revert if not in tree
        bytes32 leaf = keccak256(abi.encodePacked(account, balance));
        bool isValidLeaf = MerkleProof.verify(proof, merkleRoot, leaf);
        require(isValidLeaf, "NotInMerkle");
    }
}