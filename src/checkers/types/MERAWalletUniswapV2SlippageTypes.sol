// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.34;

/// @notice Types for MERA Uniswap V2 oracle slippage checker configuration.
library MERAWalletUniswapV2SlippageTypes {
    /// @dev ABI payload for {IMERAWalletTransactionChecker-applyConfig} on the slippage checker.
    struct UniswapV2SlippageCheckerConfig {
        /// @dev Optional ERC20 allowlist contract; address(0) disables per-wallet asset gating for that wallet.
        address assetWhitelist;
    }

    /// @dev Swap snapshot: balances and path endpoints recorded in the before-hook, read in the after-hook for oracle comparison.
    struct Snapshot {
        address token0Path;
        address token1Path;
        address priceFeed0;
        address priceFeed1;
        uint256 erc20Bal0;
        uint256 erc20Bal1;
        uint256 ethBal;
        bool ethIn;
        bool ethOut;
        bool active;
    }
}
