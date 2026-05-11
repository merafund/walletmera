// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.34;

/// @notice Minimal Chainlink-style price feed (Aggregator V3).
interface IAggregatorV3 {
    /// @notice Number of decimals used by the feed answer.
    /// @return Feed decimal precision.
    function decimals() external view returns (uint8);

    /// @notice Returns the latest feed round data.
    /// @return roundId Latest round id.
    /// @return answer Latest price answer.
    /// @return startedAt Timestamp when the round started.
    /// @return updatedAt Timestamp when the answer was updated.
    /// @return answeredInRound Round id in which the answer was computed.
    function latestRoundData()
        external
        view
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound);
}
