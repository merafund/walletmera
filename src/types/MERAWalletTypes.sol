// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.34;

/// @notice Shared structs and enums for MERA wallet contracts.
library MERAWalletTypes {
    /// @notice Per-role policy for one call path.
    struct RoleCallPolicy {
        /// @notice Required timelock delay before this role may execute the call path.
        uint32 delay;
        /// @notice Whether this role is forbidden from using the call path.
        bool forbidden;
        /// @notice Whether this policy may be used for calls that forward native ETH.
        bool allowValue;
    }

    /// @notice Execution policy for a target, selector, or target-selector pair.
    struct CallPathPolicy {
        /// @notice Policy applied to the primary role.
        RoleCallPolicy primary;
        /// @notice Policy applied to the backup role.
        RoleCallPolicy backup;
        /// @notice Required delay for the emergency role.
        uint32 emergencyDelay;
        /// @notice Whether a policy is explicitly configured.
        bool exists;
    }

    /// @notice One external call in a wallet execution batch.
    struct Call {
        /// @notice Contract or account called by the wallet.
        address target;
        /// @notice Native ETH value forwarded with the call.
        uint256 value;
        /// @notice Calldata sent to `target`.
        bytes data;
        /// @notice Optional checker used only for this call.
        address checker;
        /// @notice Opaque optional checker data consumed by `checker`.
        bytes checkerData;
    }

    /// @notice Per-address optional checker policy.
    struct OptionalChecker {
        /// @notice Whether the checker may be referenced by individual calls.
        bool allowed;
        /// @notice Whether the checker before-hook is enabled.
        bool enableBefore;
        /// @notice Whether the checker after-hook is enabled.
        bool enableAfter;
    }

    /// @notice One entry for {setOptionalCheckers} batch updates.
    struct OptionalCheckerUpdate {
        /// @notice Checker contract to update.
        address checker;
        /// @notice Whether the checker should be allowed after the update.
        bool allowed;
        /// @notice Optional encoded checker configuration applied when `allowed` is true.
        bytes config;
    }

    /// @notice One entry for {setRequiredCheckers} batch updates.
    struct RequiredCheckerUpdate {
        /// @notice Checker contract to update.
        address checker;
        /// @notice Whether the checker should be registered as required.
        bool enabled;
        /// @notice Optional encoded checker configuration applied when `enabled` is true.
        bytes config;
    }

    /// @notice Wallet controller role.
    enum Role {
        /// @notice No controller role.
        None,
        /// @notice Primary controller role.
        Primary,
        /// @notice Backup controller role.
        Backup,
        /// @notice Emergency controller role.
        Emergency
    }

    /// @notice Lifecycle status of a proposed wallet operation.
    /// @dev Values appended at the end only (storage compatibility). Vetoed is a timelock pause applied by agents until cleared by a controller.
    enum OperationStatus {
        /// @notice Operation id has no stored operation.
        None,
        /// @notice Operation exists and is waiting for execution, cancellation, or veto.
        Pending,
        /// @notice Operation has been executed.
        Executed,
        /// @notice Operation has been cancelled.
        Cancelled,
        /// @notice Operation has been vetoed until a controller clears the veto.
        Vetoed
    }

    /// @notice Policy that controls who is allowed to execute a pending operation.
    enum RelayExecutorPolicy {
        /// @notice Only wallet core execution paths may execute.
        CoreExecute,
        /// @notice Any address may execute after the timelock.
        Anyone,
        /// @notice Only the designated executor may execute.
        Designated,
        /// @notice Only addresses committed in the executor whitelist may execute.
        Whitelist
    }

    /// @notice Relay configuration used by {proposeTransactionWithRelay}.
    struct RelayProposeConfig {
        /// @notice Executor authorization policy for the pending operation.
        RelayExecutorPolicy relayPolicy;
        /// @notice Executor allowed when `relayPolicy` is `Designated`.
        address designatedExecutor;
        /// @notice Hash of the executor set allowed when `relayPolicy` is `Whitelist`.
        bytes32 executorSetHash;
        /// @notice Inclusive unix timestamp by which relay execution must happen after the timelock.
        uint64 relayExecuteBefore;
    }

    /// @notice Stored core data for a pending wallet operation.
    struct PendingOperation {
        /// @notice Address that created the operation.
        address creator;
        /// @notice Effective role used by the creator.
        Role creatorRole;
        /// @notice Timestamp when the operation was created.
        uint64 createdAt;
        /// @notice Earliest timestamp when the operation may be executed.
        uint64 executeAfter;
        /// @notice User-chosen entropy mixed into the operation id hash; not a sequential nonce.
        uint256 salt;
        /// @notice Current operation lifecycle status.
        OperationStatus status;
    }

    /// @notice Relay execution metadata stored separately to avoid bloating base pending operation storage.
    struct RelayOperation {
        /// @notice Executor authorization policy.
        RelayExecutorPolicy relayPolicy;
        /// @notice Native ETH reward paid to the relay executor.
        uint256 relayReward;
        /// @notice Executor allowed when `relayPolicy` is `Designated`.
        address designatedExecutor;
        /// @notice Hash of the allowed executor set when `relayPolicy` is `Whitelist`.
        bytes32 executorSetHash;
        /// @notice Non-zero inclusive latest execution time after timelock; zero for plain proposals.
        uint64 relayExecuteBefore;
    }

    /// @notice Optional controller delegate. `Role.None` disables the agent.
    /// @dev Emergency agents: `activeFrom == 0` means lifetime not started; once set, expiry is
    ///      `activeFrom + emergencyAgentLifetime` (global, extendable e.g. via safe mode).
    ///      Other agent roles ignore `activeFrom`.
    struct Agent {
        /// @notice Maximum role level granted to the agent.
        Role roleLevel;
        /// @notice Activation timestamp for emergency agents; ignored by other roles.
        uint64 activeFrom;
    }

    /// @notice Constructor arguments for `BaseMERAWallet` (factory or direct deployment).
    struct WalletInitParams {
        /// @notice Initial primary controller.
        address initialPrimary;
        /// @notice Initial backup controller.
        address initialBackup;
        /// @notice Initial emergency controller.
        address initialEmergency;
        /// @notice Initial EIP-1271 signer.
        address initialSigner;
        /// @notice Initial guardian contract.
        address initialGuardian;
    }
}
