// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.34;

/// @notice Shared blacklist-specific types.
library MERAWalletBlacklistTypes {
    struct TargetBlockState {
        address target;
        bool blocked;
    }
}
