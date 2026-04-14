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
    function timelockByTarget(address target) external view returns (uint256 delay);
    function timelockBySelector(bytes4 selector) external view returns (uint256 delay);
    function backupBypassTarget(address target) external view returns (bool enabled);
    function backupBypassSelector(bytes4 selector) external view returns (bool enabled);
    function operations(bytes32 operationId)
        external
        view
        returns (
            address creator,
            MERAWalletTypes.Role creatorRole,
            uint64 createdAt,
            uint64 executeAfter,
            MERAWalletTypes.OperationStatus status
        );

    function setPrimary(address newPrimary) external;
    function setBackup(address newBackup) external;
    function setEmergency(address newEmergency) external;
    function setGlobalTimelock(uint256 delay) external;
    function setTargetTimelock(address target, uint256 delay) external;
    function setSelectorTimelock(bytes4 selector, uint256 delay) external;
    function setBackupTargetBypass(address target, bool enabled) external;
    function setBackupSelectorBypass(bytes4 selector, bool enabled) external;

    function executeTransaction(MERAWalletTypes.Call[] calldata calls) external payable;
    function proposeTransaction(MERAWalletTypes.Call[] calldata calls) external returns (bytes32 operationId);
    function executePending(MERAWalletTypes.Call[] calldata calls) external payable;
    function cancelPending(bytes32 operationId) external;

    function getOperationId(MERAWalletTypes.Call[] calldata calls) external view returns (bytes32);
    function getRequiredDelay(MERAWalletTypes.Call[] calldata calls) external view returns (uint256);

    function set1271Signer(address signer) external;
    function isValidSignature(bytes32 hash, bytes calldata signature) external view returns (bytes4);
}
