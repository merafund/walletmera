// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.34;

import {MERAWalletTypes} from "../types/MERAWalletTypes.sol";

/// @notice Events emitted by BaseMERAWallet.
interface IBaseMERAWalletEvents {
    event PrimaryUpdated(address indexed previousPrimary, address indexed newPrimary, address indexed caller);
    event BackupUpdated(address indexed previousBackup, address indexed newBackup, address indexed caller);
    event EmergencyUpdated(address indexed previousEmergency, address indexed newEmergency, address indexed caller);
    event GlobalTimelockUpdated(uint256 previousDelay, uint256 newDelay, address indexed caller);
    event TargetCallPolicyUpdated(
        address indexed target,
        MERAWalletTypes.CallPathPolicy previousPolicy,
        MERAWalletTypes.CallPathPolicy newPolicy,
        address indexed caller
    );
    event SelectorCallPolicyUpdated(
        bytes4 indexed selector,
        MERAWalletTypes.CallPathPolicy previousPolicy,
        MERAWalletTypes.CallPathPolicy newPolicy,
        address indexed caller
    );
    event TargetSelectorCallPolicyUpdated(
        address indexed target,
        bytes4 indexed selector,
        MERAWalletTypes.CallPathPolicy previousPolicy,
        MERAWalletTypes.CallPathPolicy newPolicy,
        bool configured,
        address indexed caller
    );
    event RequiredCheckerUpdated(
        address indexed checker, bool beforeEnabled, bool afterEnabled, address indexed caller
    );
    event OptionalCheckerUpdated(
        address indexed checker, bool allowed, bool beforeEnabled, bool afterEnabled, address indexed caller
    );
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
    event ImmediateTransactionExecuted(bytes32 indexed operationId, uint256 indexed salt, address indexed executor);
    event EIP1271SignerUpdated(address indexed previousSigner, address indexed newSigner, address indexed caller);
    event ControllerAgentUpdated(
        address indexed agent, bool enabled, MERAWalletTypes.Role roleLevel, address indexed caller
    );
    event PrimaryFreezeUpdated(bool frozen, address indexed caller);
    event BackupFreezeUpdated(bool frozen, address indexed caller);
    event LifeControlUpdated(bool enabled, uint256 timeout, address indexed caller);
    event LifeControllerUpdated(address indexed controller, bool enabled, address indexed caller);
    event LifeHeartbeatConfirmed(address indexed controller, uint256 timestamp);
}
