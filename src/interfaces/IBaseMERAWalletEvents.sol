// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.34;

import {MERAWalletTypes} from "../types/MERAWalletTypes.sol";

/// @notice Events emitted by BaseMERAWallet.
interface IBaseMERAWalletEvents {
    event PrimaryUpdated(address indexed previousPrimary, address indexed newPrimary, address indexed caller);
    event BackupUpdated(address indexed previousBackup, address indexed newBackup, address indexed caller);
    event EmergencyUpdated(address indexed previousEmergency, address indexed newEmergency, address indexed caller);
    event GlobalTimelockUpdated(uint256 previousDelay, uint256 newDelay, address indexed caller);
    event TargetTimelockUpdated(
        address indexed target,
        uint248 previousDelay,
        uint8 previousLevel,
        uint248 newDelay,
        uint8 newLevel,
        address indexed caller
    );
    event SelectorTimelockUpdated(
        bytes4 indexed selector,
        uint248 previousDelay,
        uint8 previousLevel,
        uint248 newDelay,
        uint8 newLevel,
        address indexed caller
    );
    event BackupTargetBypassUpdated(address indexed target, bool enabled, address indexed caller);
    event BackupSelectorBypassUpdated(bytes4 indexed selector, bool enabled, address indexed caller);
    event TransactionProposed(
        bytes32 indexed operationId,
        uint256 indexed nonce,
        address indexed creator,
        MERAWalletTypes.Role creatorRole,
        uint256 executeAfter,
        uint256 requiredDelay
    );
    event PendingTransactionExecuted(bytes32 indexed operationId, uint256 indexed nonce, address indexed executor);
    event PendingTransactionCancelled(bytes32 indexed operationId, uint256 indexed nonce, address indexed cancelledBy);
    event ImmediateTransactionExecuted(bytes32 indexed operationId, uint256 indexed nonce, address indexed executor);
    event EIP1271SignerUpdated(address indexed previousSigner, address indexed newSigner, address indexed caller);
}
