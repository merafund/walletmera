// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.34;

import {MERAWalletTypes} from "../types/MERAWalletTypes.sol";

/// @notice Events emitted by BaseMERAWallet.
interface IBaseMERAWalletEvents {
    /// @notice Emitted when the primary controller changes.
    event PrimaryUpdated(address indexed previousPrimary, address indexed newPrimary);
    /// @notice Emitted when the backup controller changes.
    event BackupUpdated(address indexed previousBackup, address indexed newBackup);
    /// @notice Emitted when the emergency controller changes.
    event EmergencyUpdated(address indexed previousEmergency, address indexed newEmergency);
    /// @notice Emitted when the guardian changes.
    event GuardianUpdated(address indexed previousGuardian, address indexed newGuardian);
    /// @notice Emitted when a role timelock changes.
    event RoleTimelockUpdated(MERAWalletTypes.Role indexed role, uint256 previousDelay, uint256 newDelay);
    /// @notice Emitted when a target-level call policy changes.
    event TargetCallPolicyUpdated(
        address indexed target, MERAWalletTypes.CallPathPolicy previousPolicy, MERAWalletTypes.CallPathPolicy newPolicy
    );
    /// @notice Emitted when a selector-level call policy changes.
    event SelectorCallPolicyUpdated(
        bytes4 indexed selector, MERAWalletTypes.CallPathPolicy previousPolicy, MERAWalletTypes.CallPathPolicy newPolicy
    );
    /// @notice Emitted when a target-selector call policy changes.
    event TargetSelectorCallPolicyUpdated(
        address indexed target,
        bytes4 indexed selector,
        MERAWalletTypes.CallPathPolicy previousPolicy,
        MERAWalletTypes.CallPathPolicy newPolicy,
        bool configured
    );
    /// @notice Emitted when a required checker changes.
    event RequiredCheckerUpdated(address indexed checker, bool beforeEnabled, bool afterEnabled);
    /// @notice Emitted when an optional checker changes.
    event OptionalCheckerUpdated(address indexed checker, bool allowed, bool beforeEnabled, bool afterEnabled);
    /// @notice Emitted when a timelocked transaction is proposed.
    event TransactionProposed(
        bytes32 indexed operationId,
        uint256 indexed salt,
        address indexed creator,
        MERAWalletTypes.Role creatorRole,
        uint256 executeAfter,
        uint256 requiredDelay
    );
    /// @notice Emitted when relay metadata is saved for an operation.
    event RelayOperationSaved(
        bytes32 indexed operationId,
        MERAWalletTypes.RelayExecutorPolicy relayPolicy,
        uint256 relayReward,
        address designatedExecutor,
        bytes32 executorSetHash,
        uint64 relayExecuteBefore
    );
    /// @notice Emitted when a pending transaction is executed.
    event PendingTransactionExecuted(bytes32 indexed operationId, uint256 indexed salt, address indexed executor);
    /// @notice Emitted when a pending transaction is cancelled.
    event PendingTransactionCancelled(bytes32 indexed operationId, uint256 indexed salt, address indexed cancelledBy);
    /// @notice Emitted when a pending transaction is vetoed.
    event PendingTransactionVetoed(bytes32 indexed operationId, uint256 indexed salt, address indexed vetoedBy);
    /// @notice Emitted when a veto is cleared.
    event PendingTransactionVetoCleared(bytes32 indexed operationId, uint256 indexed salt, address indexed clearedBy);
    /// @notice Emitted when older pending transactions are invalidated.
    event PendingTransactionsInvalidated(
        uint256 previousInvalidBefore, uint256 newInvalidBefore, uint256 previousPendingTransactionsCount
    );
    /// @notice Emitted when an immediate transaction is executed.
    event ImmediateTransactionExecuted(bytes32 indexed operationId, uint256 indexed salt, address indexed executor);
    /// @notice Emitted when the EIP-1271 signer changes.
    event EIP1271SignerUpdated(address indexed previousSigner, address indexed newSigner);
    /// @notice Emitted when an agent role changes.
    event AgentUpdated(address indexed agent, MERAWalletTypes.Role roleLevel, uint64 activeFrom);
    /// @notice Emitted when emergency-agent lifetime changes.
    event EmergencyAgentLifetimeUpdated(uint256 previousLifetime, uint256 newLifetime);
    /// @notice Emitted when primary freeze state changes.
    event PrimaryFreezeUpdated(bool frozen);
    /// @notice Emitted when backup freeze state changes.
    event BackupFreezeUpdated(bool frozen);
    /// @notice Emitted when life-control config changes.
    event LifeControlUpdated(bool enabled, uint256 timeout);
    /// @notice Emitted when a life controller changes.
    event LifeControllerUpdated(address indexed controller, bool enabled);
    /// @notice Emitted when a life controller confirms liveness.
    event LifeHeartbeatConfirmed(address indexed controller, uint256 timestamp);
    /// @notice Emitted when safe mode starts.
    event SafeModeEntered(uint256 safeModeBefore);
    /// @notice Emitted when safe mode is reset after expiry.
    event SafeModeReset();
    /// @notice Emitted when migration target changes.
    event MigrationTargetUpdated(address indexed previousTarget, address indexed newTarget);
    /// @notice Emitted when a migration transaction is executed.
    event MigrationTransactionExecuted(bytes32 indexed operationId, uint256 salt);
}
