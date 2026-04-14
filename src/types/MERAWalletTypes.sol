// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.34;

/// @notice Shared structs and enums for MERA wallet contracts.
library MERAWalletTypes {
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
        OperationStatus status;
    }
}
