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
    function globalTimelock() external view returns (uint256);
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
            bytes32 executorSetHash
        );
    function controllerAgents(address agent) external view returns (bool enabled, MERAWalletTypes.Role roleLevel);
    function frozenPrimary() external view returns (bool);
    function frozenBackup() external view returns (bool);

    function setPrimary(address newPrimary) external;
    function setBackup(address newBackup) external;
    function setEmergency(address newEmergency) external;
    function setGlobalTimelock(uint256 delay) external;
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
    /// @notice Enable or disable veto agents (may {vetoPending}). On enable, `roleLevel` follows the caller's core role.
    function setControllerAgents(address[] calldata agents, bool[] calldata enabled) external;
    /// @notice Backup or Emergency may set any value. Enabled controller agents may set primary freeze to true only via the same function (no unfreeze).
    function setFrozenPrimary(bool frozen) external;
    /// @notice Emergency may set any value. Backup-scoped controller agents may set backup freeze to true only via the same function (no unfreeze).
    function setFrozenBackup(bool frozen) external;

    function executeTransaction(MERAWalletTypes.Call[] calldata calls, uint256 salt) external payable;
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
    function vetoPending(bytes32 operationId) external;
    function clearVeto(bytes32 operationId) external;
    /// @notice Only unfrozen Primary who proposed the operation; agents use {vetoPending} instead.
    function cancelPending(bytes32 operationId) external;

    function getOperationId(MERAWalletTypes.Call[] calldata calls, uint256 salt) external view returns (bytes32);
    function getRequiredDelay(MERAWalletTypes.Call[] calldata calls) external view returns (uint256);
    function getRequiredBeforeCheckers() external view returns (address[] memory);
    function getRequiredAfterCheckers() external view returns (address[] memory);
    function isLifeController(address controller) external view returns (bool);

    function set1271Signer(address signer) external;
    function isValidSignature(bytes32 hash, bytes calldata signature) external view returns (bytes4);
}
