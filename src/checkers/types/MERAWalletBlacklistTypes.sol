// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.34;

/// @notice Shared blacklist-specific types.
library MERAWalletBlacklistTypes {
    /// @notice Target blocklist state used in batch updates.
    struct TargetBlockState {
        /// @notice Target address to update.
        address target;
        /// @notice Whether the target should be blocked.
        bool blocked;
    }
}
