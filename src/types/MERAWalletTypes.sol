// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.34;

/// @notice Shared structs and enums for MERA wallet contracts.
library MERAWalletTypes {
    struct TimelockRule {
        uint248 delay;
        uint8 level;
    }

    struct Call {
        address target;
        uint256 value;
        bytes data;
    }

    enum Role {
        None,
        Primary,
        Backup,
        Emergency
    }

    enum OperationStatus {
        None,
        Pending,
        Executed,
        Cancelled
    }

    struct PendingOperation {
        address creator;
        Role creatorRole;
        uint64 createdAt;
        uint64 executeAfter;
        uint256 nonce;
        OperationStatus status;
    }
}
