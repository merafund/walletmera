// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.34;

/// @notice Custom errors for Uniswap V2 oracle slippage checker.
interface IMERAWalletUniswapV2SlippageErrors {
    /// @notice Address argument is invalid.
    error SlippageInvalidAddress();
    /// @notice Oracle deviation bound is invalid.
    error SlippageInvalidDeviationBps();
    /// @notice Oracle staleness bound is invalid.
    error SlippageInvalidStaleSeconds();
    /// @notice Router target is not allowed.
    error RouterNotAllowed(address router, uint256 callId);
    /// @notice Router selector is not supported by this checker.
    error UnsupportedRouterCall(bytes4 selector);
    /// @notice Swap path has fewer than two assets.
    error PathTooShort();
    /// @notice Price feed is not configured for a token.
    error PriceFeedNotSet(address token);
    /// @notice Oracle answer is older than the configured staleness bound.
    error StaleOraclePrice(address token, uint256 updatedAt);
    /// @notice Oracle answer is non-positive.
    error OracleAnswerInvalid(address token);
    /// @notice Sequencer uptime feed grace period is invalid.
    error InvalidSequencerGracePeriod();
    /// @notice Sequencer uptime feed reports the sequencer is down.
    error SequencerDown();
    /// @notice Sequencer uptime feed data is invalid.
    error SequencerUptimeFeedInvalid();
    /// @notice Sequencer has recovered, but the grace period has not elapsed.
    error SequencerGracePeriodNotOver(uint256 startedAt);
    /// @notice Measured balance deltas are zero or invalid.
    error InvalidMeasuredAmounts();
    /// @notice Swap output is worse than oracle-implied output beyond tolerance.
    error SwapWorseThanOracle();
    /// @notice Caller is not authorized to pause the checker.
    error SlippageNotPauseAuthorized();
    /// @notice Parallel update arrays have different lengths.
    error SlippageArrayLengthMismatch();
    /// @notice Per-call checker data is invalid.
    error InvalidCheckerData();
    /// @notice Path endpoint token is rejected by the configured {IMERAWalletAssetWhiteList}.
    error AssetNotWhitelisted(address token, uint256 callId);
}
