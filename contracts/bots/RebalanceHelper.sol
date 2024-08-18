// SPDX-License-Identifier: BSUL-1.1
pragma solidity ^0.8.19;

interface NotionalProxy {
    function rebalance(uint16 currencyId) external;

    function checkRebalance() external view returns (uint16[] memory currencyId);
}

contract RebalanceHelper {
    event RebalancingFailed(uint16 currencyId, bytes reason);
    event RebalancingSucceeded(uint16 currencyId);

    error CurrencyIdsLengthCannotBeZero();
    error CurrencyIdsNeedToBeSorted();
    error Unauthorized();

    address public constant RELAYER_ADDRESS = 0x745915418D8B70f39ce9e61A965cBB0C87f9f7Ed; 
    uint256 public constant DELAY_AFTER_FAILURE = 10 minutes;
    NotionalProxy public immutable NOTIONAL;

    mapping(uint16 currencyId => uint32 lastFailedRebalanceTimestamp) public failedRebalanceMap;

    constructor(NotionalProxy notionalAddress) {
        NOTIONAL = notionalAddress;
    }

    function checkAndRebalance() external {
        uint16[] memory currencyIdsToProcess = checkRebalance();
        if (currencyIdsToProcess.length > 0) {
            rebalanceAll(currencyIdsToProcess);
        }
    }


    function rebalanceAll(uint16[] memory currencyIds) public {
        if (currencyIds.length == 0) {
            revert CurrencyIdsLengthCannotBeZero();
        }
        if (msg.sender != RELAYER_ADDRESS) {
            revert Unauthorized();
        }

        for (uint256 i = 0; i < currencyIds.length; i++) {
            uint16 currencyId = currencyIds[i];
            // ensure currency ids are unique and sorted
            if (i != 0 && currencyIds[i - 1] < currencyId) {
                revert CurrencyIdsNeedToBeSorted();
            }

            // Rebalance each of the currencies provided.
            try NOTIONAL.rebalance(currencyId) {
                emit RebalancingSucceeded(currencyId);
            } catch (bytes memory reason) {
                failedRebalanceMap[currencyId] = uint32(block.timestamp);
                emit RebalancingFailed(currencyId, reason);
            }
        }
    }

    function checkRebalance()
        public
        view
        returns (uint16[] memory currencyIdsToProcess)
    {
        uint16[] memory currencyIds = NOTIONAL.checkRebalance();

        // skip any currency that failed in previous rebalance that
        // happened after block.timestamp - DELAY_AFTER_FAILURE period
        uint16 numOfCurrencyIdsToProcess = 0;
        for (uint256 i = 0; i < currencyIds.length; i++) {
            if (
                failedRebalanceMap[currencyIds[i]] + DELAY_AFTER_FAILURE <
                block.timestamp
            ) {
                currencyIds[numOfCurrencyIdsToProcess++] = currencyIds[i];
            }
        }

        if (numOfCurrencyIdsToProcess > 0) {
            currencyIdsToProcess = new uint16[](
                numOfCurrencyIdsToProcess
            );
            for (uint256 i = 0; i < numOfCurrencyIdsToProcess; i++) {
                currencyIdsToProcess[i] = currencyIds[i];
            }
        }
    }
}