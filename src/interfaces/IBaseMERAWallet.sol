// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.34;

import {MERAWalletTypes} from "../types/MERAWalletTypes.sol";

/// @notice External API of BaseMERAWallet (functions and public mapping getters).
interface IBaseMERAWallet {
    receive() external payable;

    function primary() external view returns (address);
    function backup() external view returns (address);
    function emergency() external view returns (address);
    function eip1271Signer() external view returns (address);
    function globalTimelock() external view returns (uint256);
    function whitelistedChecker(address checker)
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
            uint256 nonce,
            MERAWalletTypes.OperationStatus status
        );
    function controllerAgents(address agent)
        external
        view
        returns (bool enabled, MERAWalletTypes.Role executionRole, MERAWalletTypes.Role removalMinRole);

    function setPrimary(address newPrimary) external;
    function setBackup(address newBackup) external;
    function setEmergency(address newEmergency) external;
    function setGlobalTimelock(uint256 delay) external;
    function setTargetCallPolicy(address target, MERAWalletTypes.CallPathPolicy calldata policy) external;
    function setSelectorCallPolicy(bytes4 selector, MERAWalletTypes.CallPathPolicy calldata policy) external;
    /// @param enabled If true, registers or syncs required checkers from `checker.hookModes()`. If false, removes `checker` from required lists.
    function setRequiredChecker(address checker, bool enabled) external;
    function setWhitelistedChecker(address checker, bool allowed) external;
    /// @notice Assign or update a delegate controller, or disable one (`config.enabled == false`). Calldata `removalMinRole` is ignored on enable; it is set from the caller's core role.
    function setControllerAgent(address agent, MERAWalletTypes.ControllerAgent calldata config) external;

    function executeTransaction(MERAWalletTypes.Call[] calldata calls, uint256 nonce) external payable;
    function proposeTransaction(MERAWalletTypes.Call[] calldata calls, uint256 nonce)
        external
        returns (bytes32 operationId);
    function executePending(MERAWalletTypes.Call[] calldata calls, uint256 nonce) external payable;
    function cancelPending(bytes32 operationId) external;

    function getOperationId(MERAWalletTypes.Call[] calldata calls, uint256 nonce) external view returns (bytes32);
    function getRequiredDelay(MERAWalletTypes.Call[] calldata calls) external view returns (uint256);
    function getRequiredBeforeCheckers() external view returns (address[] memory);
    function getRequiredAfterCheckers() external view returns (address[] memory);

    function set1271Signer(address signer) external;
    function isValidSignature(bytes32 hash, bytes calldata signature) external view returns (bytes4);
}
