// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.34;

import {MERAWalletTypes} from "../types/MERAWalletTypes.sol";

/// @notice Events emitted by BaseMERAWallet.
interface IBaseMERAWalletEvents {
    event PrimaryUpdated(address indexed previousPrimary, address indexed newPrimary);
    event BackupUpdated(address indexed previousBackup, address indexed newBackup);
    event EmergencyUpdated(address indexed previousEmergency, address indexed newEmergency);
    event GuardianUpdated(address indexed previousGuardian, address indexed newGuardian);
    event RoleTimelockUpdated(MERAWalletTypes.Role indexed role, uint256 previousDelay, uint256 newDelay);
    event TargetCallPolicyUpdated(
        address indexed target, MERAWalletTypes.CallPathPolicy previousPolicy, MERAWalletTypes.CallPathPolicy newPolicy
    );
    event SelectorCallPolicyUpdated(
        bytes4 indexed selector, MERAWalletTypes.CallPathPolicy previousPolicy, MERAWalletTypes.CallPathPolicy newPolicy
    );
    event TargetSelectorCallPolicyUpdated(
        address indexed target,
        bytes4 indexed selector,
        MERAWalletTypes.CallPathPolicy previousPolicy,
        MERAWalletTypes.CallPathPolicy newPolicy,
        bool configured
    );
    event RequiredCheckerUpdated(address indexed checker, bool beforeEnabled, bool afterEnabled);
    event OptionalCheckerUpdated(address indexed checker, bool allowed, bool beforeEnabled, bool afterEnabled);
    event TransactionProposed(
        bytes32 indexed operationId,
        uint256 indexed salt,
        address indexed creator,
        MERAWalletTypes.Role creatorRole,
        uint256 executeAfter,
        uint256 requiredDelay
    );
    event RelayOperationSaved(
        bytes32 indexed operationId,
        MERAWalletTypes.RelayExecutorPolicy relayPolicy,
        uint256 relayReward,
        address designatedExecutor,
        bytes32 executorSetHash,
        uint64 relayExecuteBefore
    );
    event PendingTransactionExecuted(bytes32 indexed operationId, uint256 indexed salt, address indexed executor);
    event PendingTransactionCancelled(bytes32 indexed operationId, uint256 indexed salt, address indexed cancelledBy);
    event PendingTransactionVetoed(bytes32 indexed operationId, uint256 indexed salt, address indexed vetoedBy);
    event PendingTransactionVetoCleared(bytes32 indexed operationId, uint256 indexed salt, address indexed clearedBy);
    event PendingTransactionsInvalidated(
        uint256 previousInvalidBefore, uint256 newInvalidBefore, uint256 previousPendingTransactionsCount
    );
    event ImmediateTransactionExecuted(bytes32 indexed operationId, uint256 indexed salt, address indexed executor);
    event EIP1271SignerUpdated(address indexed previousSigner, address indexed newSigner);
    event AgentUpdated(address indexed agent, MERAWalletTypes.Role roleLevel, uint64 activeFrom);
    event EmergencyAgentLifetimeUpdated(uint256 previousLifetime, uint256 newLifetime);
    event PrimaryFreezeUpdated(bool frozen);
    event BackupFreezeUpdated(bool frozen);
    event LifeControlUpdated(bool enabled, uint256 timeout);
    event LifeControllerUpdated(address indexed controller, bool enabled);
    event LifeHeartbeatConfirmed(address indexed controller, uint256 timestamp);
    event SafeModeEntered(uint256 safeModeBefore);
    event SafeModeReset();
    event MigrationTargetUpdated(address indexed previousTarget, address indexed newTarget);
    event MigrationTransactionExecuted(bytes32 indexed operationId, uint256 salt);
}
