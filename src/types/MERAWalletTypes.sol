// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.34;

/// @notice Shared structs and enums for MERA wallet contracts.
library MERAWalletTypes {
    struct RoleCallPolicy {
        uint56 delay;
        bool forbidden;
    }

    struct CallPathPolicy {
        RoleCallPolicy primary;
        RoleCallPolicy backup;
        uint56 emergencyDelay;
        bool exists;
    }

    struct Call {
        address target;
        uint256 value;
        bytes data;
        address checker;
        bytes checkerData;
    }

    /// @dev Per-address optional checker policy: whether it may be used and which hooks run.
    struct OptionalChecker {
        bool allowed;
        bool enableBefore;
        bool enableAfter;
    }

    /// @notice One entry for {setOptionalCheckers} batch updates.
    struct OptionalCheckerUpdate {
        address checker;
        bool allowed;
        bytes config;
    }

    /// @notice One entry for {setRequiredCheckers} batch updates.
    struct RequiredCheckerUpdate {
        address checker;
        bool enabled;
        bytes config;
    }

    enum Role {
        None,
        Primary,
        Backup,
        Emergency
    }

    /// @dev Values appended at the end only (storage compatibility). Vetoed is a timelock pause applied by agents until cleared by a controller.
    enum OperationStatus {
        None,
        Pending,
        Executed,
        Cancelled,
        Vetoed
    }

    /// @notice Policy that controls who is allowed to execute a pending operation.
    enum RelayExecutorPolicy {
        CoreExecute,
        Anyone,
        Designated,
        Whitelist
    }

    /// @notice Relay configuration used by {proposeTransactionWithRelay}.
    struct RelayProposeConfig {
        RelayExecutorPolicy relayPolicy;
        address designatedExecutor;
        bytes32 executorSetHash;
        /// @dev Unix timestamp (inclusive): execution must happen on or before this time once the timelock has passed.
        uint64 relayExecuteBefore;
    }

    struct PendingOperation {
        address creator;
        Role creatorRole;
        uint64 createdAt;
        uint64 executeAfter;
        /// @dev User-chosen entropy mixed into the operation id hash; not a sequential nonce.
        uint256 salt;
        OperationStatus status;
    }

    /// @notice Relay execution metadata stored separately to avoid bloating base pending operation storage.
    struct RelayOperation {
        RelayExecutorPolicy relayPolicy;
        uint256 relayReward;
        address designatedExecutor;
        bytes32 executorSetHash;
        /// @dev Non-zero: inclusive latest execution time after timelock. Zero: no relay deadline (plain {proposeTransaction} path).
        uint64 relayExecuteBefore;
    }

    /// @notice Optional controller delegate. `Role.None` disables the agent.
    /// @dev Emergency agents: `activeUntil == 0` means lifetime not started; once non-zero, expiry is enforced.
    ///      Other agent roles ignore `activeUntil`.
    struct Agent {
        Role roleLevel;
        uint64 activeUntil;
    }

    /// @notice Constructor arguments for `BaseMERAWallet` (factory or direct deployment).
    struct WalletInitParams {
        address initialPrimary;
        address initialBackup;
        address initialEmergency;
        address initialSigner;
        address initialGuardian;
    }
}
