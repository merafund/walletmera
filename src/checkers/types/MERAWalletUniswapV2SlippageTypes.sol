// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.34;

/// @notice Types for MERA Uniswap V2 oracle slippage checker configuration.
library MERAWalletUniswapV2SlippageTypes {
    /// @dev ABI payload for {IMERAWalletTransactionChecker-applyConfig} on the slippage checker.
    struct UniswapV2SlippageCheckerConfig {
        /// @dev Optional ERC20 allowlist contract; address(0) disables per-wallet asset gating for that wallet.
        address assetWhitelist;
    }
}
