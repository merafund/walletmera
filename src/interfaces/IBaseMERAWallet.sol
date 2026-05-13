// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.34;

import {MERAWalletTypes} from "../types/MERAWalletTypes.sol";

/// @notice External API of BaseMERAWallet (functions and public mapping getters).
interface IBaseMERAWallet {
    /// @notice Accepts native ETH sent to the wallet.
    receive() external payable;

    /// @notice Current primary controller.
    function primary() external view returns (address);
    /// @notice Current backup controller.
    function backup() external view returns (address);
    /// @notice Current emergency controller.
    function emergency() external view returns (address);
    /// @notice Current guardian contract.
    function guardian() external view returns (address);
    /// @notice Address bound for EIP-1271 signature validation.
    function eip1271Signer() external view returns (address);
    /// @notice Timelock delay configured for `role`.
    function roleTimelock(MERAWalletTypes.Role role) external view returns (uint256);
    /// @notice Lifetime of emergency-level agents after activation.
    function emergencyAgentLifetime() external view returns (uint256);
    /// @notice Required heartbeat interval for life-control mode.
    function lifeHeartbeatTimeout() external view returns (uint256);
    /// @notice Timestamp of the latest accepted life-controller heartbeat.
    function lastLifeHeartbeatAt() external view returns (uint256);
    /// @notice Whether life-control checks are enabled.
    function lifeControlEnabled() external view returns (bool);
    /// @notice Number of currently tracked pending transactions.
    function pendingTransactionsCount() external view returns (uint256);
    /// @notice Timestamp before which pending transactions are considered invalidated.
    function pendingTransactionsInvalidBefore() external view returns (uint256);
    /// @notice Optional checker permission and hook flags.
    /// @param checker Checker address.
    /// @return allowed Whether the checker may be used by per-call config.
    /// @return enableBefore Whether its before-hook is enabled.
    /// @return enableAfter Whether its after-hook is enabled.
    function whitelistOptionalChecker(address checker)
        external
        view
        returns (bool allowed, bool enableBefore, bool enableAfter);
    /// @notice Stored operation and relay metadata for `operationId`.
    /// @param operationId Operation id returned by proposal helpers.
    function operations(bytes32 operationId)
        external
        view
        returns (
            address creator,
            MERAWalletTypes.Role creatorRole,
            uint64 createdAt,
            uint64 executeAfter,
            uint256 salt,
            MERAWalletTypes.OperationStatus status,
            MERAWalletTypes.RelayExecutorPolicy relayPolicy,
            uint256 relayReward,
            address designatedExecutor,
            bytes32 executorSetHash,
            uint64 relayExecuteBefore
        );
    /// @notice Agent role and activation timestamp for `agent`.
    function agents(address agent) external view returns (MERAWalletTypes.Role roleLevel, uint64 activeFrom);
    /// @notice Whether primary-controlled actions are frozen.
    function frozenPrimary() external view returns (bool);
    /// @notice Whether backup-controlled actions are frozen.
    function frozenBackup() external view returns (bool);
    /// @notice Timestamp until which safe mode blocks wallet execution.
    function safeModeBefore() external view returns (uint256);
    /// @notice Whether the one-time safe-mode activation has been used.
    function safeModeUsed() external view returns (bool);
    /// @notice Target allowed for migration-mode calls.
    function migrationTarget() external view returns (address);

    /// @notice Initializes a clone using immutable args embedded by the factory.
    function initializeFromImmutableArgs() external;
    /// @notice Updates the primary controller.
    function setPrimary(address newPrimary) external;
    /// @notice Updates the backup controller.
    function setBackup(address newBackup) external;
    /// @notice Updates the emergency controller.
    function setEmergency(address newEmergency) external;
    /// @notice Updates the guardian contract.
    function setGuardian(address newGuardian) external;
    /// @notice Sets the default timelock delay for `role`.
    function setRoleTimelock(MERAWalletTypes.Role role, uint256 delay) external;
    /// @notice Sets the activation lifetime for emergency-level agents.
    function setEmergencyAgentLifetime(uint256 lifetime) external;
    /// @notice Enables or disables life control and sets heartbeat timeout.
    function setLifeControl(bool enabled, uint256 timeout) external;
    /// @notice Batch-updates life-controller permissions.
    function setLifeControllers(address[] calldata controllers, bool enabled) external;
    /// @notice Records a heartbeat from an enabled life controller.
    function confirmAlive() external;
    /// @notice Batch-updates policies keyed by target address.
    function setTargetCallPolicies(address[] calldata targets, MERAWalletTypes.CallPathPolicy[] calldata policies)
        external;
    /// @notice Batch-updates policies keyed by selector.
    function setSelectorCallPolicies(bytes4[] calldata selectors, MERAWalletTypes.CallPathPolicy[] calldata policies)
        external;
    /// @notice Pair (target, selector) policies in parallel arrays. When `policies[i].exists` is true, stores that policy; when false, removes that pair (other fields ignored).
    function setTargetSelectorCallPolicies(
        address[] calldata targets,
        bytes4[] calldata selectors,
        MERAWalletTypes.CallPathPolicy[] calldata policies
    ) external;
    /// @param updates Per entry: if `enabled` is true, registers or syncs from `checker.hookModes()`; if false, removes from required lists.
    /// @dev `config` is passed to `applyConfig` when `enabled` and non-empty (same rules as each single entry in the batch).
    function setRequiredCheckers(MERAWalletTypes.RequiredCheckerUpdate[] calldata updates) external;
    /// @dev `config` is passed to `applyConfig` when allowed and non-empty (same rules as each single entry in the batch).
    function setOptionalCheckers(MERAWalletTypes.OptionalCheckerUpdate[] calldata updates) external;
    /// @notice Configure controller agents. `Role.None` disables an agent.
    /// @dev `agentAddresses[i]` cannot be this wallet's own address when `roleLevels[i]` is not `None`.
    function setAgents(address[] calldata agentAddresses, MERAWalletTypes.Role[] calldata roleLevels) external;
    /// @notice Same-or-higher agents/core controllers may freeze; only strictly higher core controllers may unfreeze; guardian may freeze only.
    function setFrozenPrimary(bool frozen) external;
    /// @notice Same-or-higher agents/core controllers may freeze; only strictly higher core controllers may unfreeze; guardian may freeze only.
    function setFrozenBackup(bool frozen) external;
    /// @notice Enter safe mode: blocks all transaction execution/proposal for `duration` seconds. One-time use.
    /// @dev Callable only by emergency address or emergency-level controller agent.
    function enterSafeMode(uint256 duration) external;
    /// @notice Reset safe mode flag after expiry, re-enabling future use. Only callable by emergency after safeModeBefore has passed.
    function resetSafeMode() external;
    /// @notice Set the migration target address. Only callable by emergency. Set to address(0) to deactivate.
    function setMigrationTarget(address target) external;
    /// @notice Invalidates pending transactions created before the current timestamp and resets the pending counter.
    function invalidatePendingTransactionsBeforeCurrentTimestamp() external;

    /// @notice Executes a batch immediately when caller role and call policies permit it.
    /// @param calls Calls executed by the wallet.
    /// @param salt User-chosen salt included in the operation id.
    function executeTransaction(MERAWalletTypes.Call[] calldata calls, uint256 salt) external payable;
    /// @notice Execute migration calls (transferOwnership / grantRole to migrationTarget) immediately without timelock.
    /// @dev Each call must use `value == 0`.
    function executeMigrationTransaction(MERAWalletTypes.Call[] calldata calls, uint256 salt) external payable;
    /// @notice Proposes a timelocked transaction batch.
    /// @param calls Calls to execute after the required delay.
    /// @param salt User-chosen salt included in the operation id.
    /// @return operationId Id of the stored pending operation.
    function proposeTransaction(MERAWalletTypes.Call[] calldata calls, uint256 salt)
        external
        returns (bytes32 operationId);
    /// @notice Proposes a timelocked transaction batch with relay execution metadata.
    /// @param calls Calls to execute after the required delay.
    /// @param salt User-chosen salt included in the operation id.
    /// @param relayConfig Relay authorization and deadline config.
    /// @return operationId Id of the stored pending operation.
    function proposeTransactionWithRelay(
        MERAWalletTypes.Call[] calldata calls,
        uint256 salt,
        MERAWalletTypes.RelayProposeConfig calldata relayConfig
    ) external payable returns (bytes32 operationId);
    /// @notice Executes a pending operation through the default core execution path.
    /// @param calls Calls matching the proposed operation.
    /// @param salt Salt matching the proposed operation.
    function executePending(MERAWalletTypes.Call[] calldata calls, uint256 salt) external payable;
    /// @notice Executes a pending operation using an executor whitelist proof payload.
    /// @param calls Calls matching the proposed operation.
    /// @param salt Salt matching the proposed operation.
    /// @param executorWhitelist Allowed executor set used to prove whitelist membership.
    function executePending(MERAWalletTypes.Call[] calldata calls, uint256 salt, address[] calldata executorWhitelist)
        external
        payable;
    /// @notice Same-or-higher agents/core controllers may veto.
    function vetoPending(bytes32 operationId) external;
    /// @notice Unfrozen core controller; role rank Primary=1 .. Emergency=3 (see MERAWalletConstants). Requires `_roleRank(caller) > _roleRank(operation.creatorRole)`.
    function clearVeto(bytes32 operationId) external;
    /// @notice Core controller; role rank Primary=1 .. Emergency=3. Cancel if `_roleRank(caller) >= _roleRank(operation.creatorRole)`; operations created by Emergency cannot be cancelled; agents use {vetoPending} instead.
    function cancelPending(bytes32 operationId) external;

    /// @notice Computes the operation id for `calls` and `salt`.
    function getOperationId(MERAWalletTypes.Call[] calldata calls, uint256 salt) external view returns (bytes32);
    /// @notice Returns the maximum required delay for `calls` under current policies.
    function getRequiredDelay(MERAWalletTypes.Call[] calldata calls) external view returns (uint256);
    /// @notice Returns required before-hook and after-hook checker lists.
    function getRequiredCheckers()
        external
        view
        returns (address[] memory beforeCheckers, address[] memory afterCheckers);
    /// @notice Returns whether `controller` may provide life-control heartbeats.
    function isLifeController(address controller) external view returns (bool);

    /// @notice Binds `eip1271Signer` to the current `primary` / `backup` / `emergency` address for the given role, or clears it when `role` is `None`.
    function set1271Signer(MERAWalletTypes.Role role) external;
    /// @notice EIP-1271 signature validation entrypoint.
    /// @param hash Signed digest.
    /// @param signature Signature bytes.
    /// @return EIP-1271 magic value when valid, otherwise invalid value.
    function isValidSignature(bytes32 hash, bytes calldata signature) external view returns (bytes4);
}
