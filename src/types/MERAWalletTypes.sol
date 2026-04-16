// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.34;

/// @notice Shared structs and enums for MERA wallet contracts.
library MERAWalletTypes {
    /// @notice Per-role delay and forbid flag for one policy dimension (single target OR single selector).
    /// @dev uint120 + bool packs to 128 bits so two roles fit in one storage slot inside CallPathPolicy.
    struct RoleCallPolicy {
        /// @dev Timelock duration for this role on this path dimension; 0 means no extra delay from this side.
        uint120 delay;
        /// @dev If true, this role must not execute calls matching this dimension (merged with OR across target/selector).
        bool forbidden;
    }

    /// @notice Primary vs backup execution policy for one target address or one function selector (one storage slot).
    struct CallPathPolicy {
        RoleCallPolicy primary;
        RoleCallPolicy backup;
    }

    struct Call {
        address target;
        uint256 value;
        bytes data;
        address checker;
        bytes checkerData;
    }

    /// @dev Per-address optional checker policy: whether it may be used and which hooks run.
    struct WhitelistChecker {
        bool allowed;
        bool enableBefore;
        bool enableAfter;
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

    /// @notice Optional veto delegate: may cancel any pending operation via {cancelPending}.
    /// @dev `removalMinRole` is set by the wallet on assign: only core controllers at or above this rank may disable the agent.
    struct ControllerAgent {
        bool enabled;
        Role removalMinRole;
    }
}
