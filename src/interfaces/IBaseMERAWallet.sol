// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.34;

import {MERAWalletTypes} from "../types/MERAWalletTypes.sol";

/// @notice External API of BaseMERAWallet (functions and public mapping getters).
interface IBaseMERAWallet {
    receive() external payable;

    function primary() external view returns (address);
    function backup() external view returns (address);
    function emergency() external view returns (address);
    function GUARDIAN() external view returns (address);
    function eip1271Signer() external view returns (address);
    function roleTimelock(MERAWalletTypes.Role role) external view returns (uint256);
    function emergencyAgentLifetime() external view returns (uint256);
    function lifeHeartbeatTimeout() external view returns (uint256);
    function lastLifeHeartbeatAt() external view returns (uint256);
    function lifeControlEnabled() external view returns (bool);
    function whitelistOptionalChecker(address checker)
        external
        view
        returns (bool allowed, bool enableBefore, bool enableAfter);
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
    function agents(address agent) external view returns (MERAWalletTypes.Role roleLevel, uint64 activeUntil);
    function frozenPrimary() external view returns (bool);
    function frozenBackup() external view returns (bool);
    function safeModeBefore() external view returns (uint256);
    function safeModeUsed() external view returns (bool);
    function migrationTarget() external view returns (address);

    function initializeFromImmutableArgs() external;
    function setPrimary(address newPrimary) external;
    function setBackup(address newBackup) external;
    function setEmergency(address newEmergency) external;
    function setGuardian(address newGuardian) external;
    function setRoleTimelock(MERAWalletTypes.Role role, uint256 delay) external;
    function setEmergencyAgentLifetime(uint256 lifetime) external;
    function setLifeControl(bool enabled, uint256 timeout) external;
    function setLifeControllers(address[] calldata controllers, bool enabled) external;
    function confirmAlive() external;
    function setTargetCallPolicies(address[] calldata targets, MERAWalletTypes.CallPathPolicy[] calldata policies)
        external;
    function setSelectorCallPolicies(bytes4[] calldata selectors, MERAWalletTypes.CallPathPolicy[] calldata policies)
        external;
    /// @notice Pair (target, selector) policies in parallel arrays. When `policies[i].exists` is true, stores that policy; when false, removes that pair (other fields ignored).
    function setTargetSelectorCallPolicies(
        address[] calldata targets,
        bytes4[] calldata selectors,
        MERAWalletTypes.CallPathPolicy[] calldata policies
    ) external;
    /// @param enabled Per checker: if true, registers or syncs from `checker.hookModes()`; if false, removes from required lists.
    function setRequiredCheckers(address[] calldata checkers, bool[] calldata enabled) external;
    /// @dev `config` is passed to `applyConfig` when allowed and non-empty (same rules as each single entry in the batch).
    function setOptionalCheckers(MERAWalletTypes.OptionalCheckerUpdate[] calldata updates) external;
    /// @notice Configure controller agents. `Role.None` disables an agent.
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

    function executeTransaction(MERAWalletTypes.Call[] calldata calls, uint256 salt) external payable;
    /// @notice Execute migration calls (transferOwnership / grantRole to migrationTarget) immediately without timelock.
    function executeMigrationTransaction(MERAWalletTypes.Call[] calldata calls, uint256 salt) external payable;
    function proposeTransaction(MERAWalletTypes.Call[] calldata calls, uint256 salt)
        external
        returns (bytes32 operationId);
    function proposeTransactionWithRelay(
        MERAWalletTypes.Call[] calldata calls,
        uint256 salt,
        MERAWalletTypes.RelayProposeConfig calldata relayConfig
    ) external payable returns (bytes32 operationId);
    function executePending(MERAWalletTypes.Call[] calldata calls, uint256 salt) external payable;
    function executePending(MERAWalletTypes.Call[] calldata calls, uint256 salt, address[] calldata executorWhitelist)
        external
        payable;
    /// @notice Same-or-higher agents/core controllers may veto.
    function vetoPending(bytes32 operationId) external;
    /// @notice Unfrozen core controller; role rank Primary=1 .. Emergency=3 (see MERAWalletConstants). Requires `_roleRank(caller) > _roleRank(operation.creatorRole)`.
    function clearVeto(bytes32 operationId) external;
    /// @notice Unfrozen core controller; role rank Primary=1 .. Emergency=3. Cancel if caller rank is at most operation creator rank; agents use {vetoPending} instead.
    function cancelPending(bytes32 operationId) external;

    function getOperationId(MERAWalletTypes.Call[] calldata calls, uint256 salt) external view returns (bytes32);
    function getRequiredDelay(MERAWalletTypes.Call[] calldata calls) external view returns (uint256);
    function getRequiredCheckers()
        external
        view
        returns (address[] memory beforeCheckers, address[] memory afterCheckers);
    function isLifeController(address controller) external view returns (bool);

    function set1271Signer(address signer) external;
    function isValidSignature(bytes32 hash, bytes calldata signature) external view returns (bytes4);
}
