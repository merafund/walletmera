// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.34;

/// @notice Custom errors for Uniswap V2 oracle slippage checker.
interface IMERAWalletUniswapV2SlippageErrors {
    error SlippageInvalidAddress();
    error SlippageInvalidDeviationBps();
    error SlippageInvalidStaleSeconds();
    error RouterNotAllowed(address router, uint256 callId);
    error UnsupportedRouterCall(bytes4 selector);
    error PathTooShort();
    error PriceFeedNotSet(address token);
    error StaleOraclePrice(address token, uint256 updatedAt);
    error OracleAnswerInvalid(address token);
    error InvalidMeasuredAmounts();
    error SwapWorseThanOracle();
    error SlippageNotPauseAuthorized();
    error SlippageArrayLengthMismatch();
}
