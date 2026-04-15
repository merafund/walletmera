// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.34;

/// @notice Shared whitelist-specific types.
library MERAWalletWhitelistTypes {
    struct TargetPermission {
        address target;
        bool allowed;
    }
}
