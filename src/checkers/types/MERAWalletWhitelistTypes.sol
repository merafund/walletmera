// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.34;

/// @notice Shared whitelist-specific types.
library MERAWalletWhitelistTypes {
    /// @notice Target allowlist state used in batch updates.
    struct TargetPermission {
        /// @notice Target address to update.
        address target;
        /// @notice Whether the target should be allowed.
        bool allowed;
    }
}
