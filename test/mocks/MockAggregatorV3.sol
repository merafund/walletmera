// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.34;

import {IAggregatorV3} from "../../src/interfaces/oracles/IAggregatorV3.sol";

/// @dev Chainlink-style price feed for tests.
contract MockAggregatorV3 is IAggregatorV3 {
    int256 public answer;
    uint8 public immutable dec;
    uint256 public updatedAtOverride;

    constructor(int256 initialAnswer, uint8 decimals_) {
        answer = initialAnswer;
        dec = decimals_;
    }

    function setAnswer(int256 a) external {
        answer = a;
    }

    function setUpdatedAt(uint256 t) external {
        updatedAtOverride = t;
    }

    function decimals() external view returns (uint8) {
        return dec;
    }

    function latestRoundData()
        external
        view
        returns (uint80 roundId, int256 answer_, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound)
    {
        uint256 ua = updatedAtOverride != 0 ? updatedAtOverride : block.timestamp;
        return (1, answer, ua, ua, 1);
    }
}
