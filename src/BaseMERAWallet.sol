// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.34;

import {MERAWalletConstants} from "./constants/MERAWalletConstants.sol";
import {MERAWalletTypes} from "./types/MERAWalletTypes.sol";
import {IBaseMERAWallet} from "./interfaces/IBaseMERAWallet.sol";
import {IBaseMERAWalletErrors} from "./interfaces/IBaseMERAWalletErrors.sol";
import {IBaseMERAWalletEvents} from "./interfaces/IBaseMERAWalletEvents.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

contract BaseMERAWallet is IBaseMERAWallet, IBaseMERAWalletEvents, IBaseMERAWalletErrors {
    address public primary;
    address public backup;
    address public emergency;
    address public eip1271Signer;

    uint256 public globalTimelock;
    mapping(address target => uint256 delay) public timelockByTarget;
    mapping(bytes4 selector => uint256 delay) public timelockBySelector;
    mapping(address target => bool enabled) public backupBypassTarget;
    mapping(bytes4 selector => bool enabled) public backupBypassSelector;
    mapping(bytes32 operationId => MERAWalletTypes.PendingOperation operation) public operations;

    constructor(address initialPrimary, address initialBackup, address initialEmergency, address initialSigner) {
        require(
            initialPrimary != address(0) && initialBackup != address(0) && initialEmergency != address(0),
            InvalidAddress()
        );

        primary = initialPrimary;
        backup = initialBackup;
        emergency = initialEmergency;

        _set1271Signer(initialSigner);
    }

    receive() external payable override {}

    function setPrimary(address newPrimary) external override {
        require(newPrimary != address(0), InvalidAddress());

        require(
            msg.sender == primary || msg.sender == backup || msg.sender == emergency,
            Unauthorized()
        );

        address previousPrimary = primary;
        primary = newPrimary;
        emit PrimaryUpdated(previousPrimary, newPrimary, msg.sender);
    }

    function setBackup(address newBackup) external override {
        require(newBackup != address(0), InvalidAddress());

        require(msg.sender == backup || msg.sender == emergency, NotAllowedRoleChange());

        address previousBackup = backup;
        backup = newBackup;
        emit BackupUpdated(previousBackup, newBackup, msg.sender);
    }

    function setEmergency(address newEmergency) external override {
        _onlyEmergency();
        require(newEmergency != address(0), InvalidAddress());

        address previousEmergency = emergency;
        emergency = newEmergency;
        emit EmergencyUpdated(previousEmergency, newEmergency, msg.sender);
    }

    function setGlobalTimelock(uint256 delay) external override {
        _onlyEmergency();
        uint256 previousDelay = globalTimelock;
        globalTimelock = delay;
        emit GlobalTimelockUpdated(previousDelay, delay, msg.sender);
    }

    function setTargetTimelock(address target, uint256 delay) external override {
        _onlyEmergency();
        uint256 previousDelay = timelockByTarget[target];
        timelockByTarget[target] = delay;
        emit TargetTimelockUpdated(target, previousDelay, delay, msg.sender);
    }

    function setSelectorTimelock(bytes4 selector, uint256 delay) external override {
        _onlyEmergency();
        uint256 previousDelay = timelockBySelector[selector];
        timelockBySelector[selector] = delay;
        emit SelectorTimelockUpdated(selector, previousDelay, delay, msg.sender);
    }

    function setBackupTargetBypass(address target, bool enabled) external override {
        _onlyEmergency();
        backupBypassTarget[target] = enabled;
        emit BackupTargetBypassUpdated(target, enabled, msg.sender);
    }

    function setBackupSelectorBypass(bytes4 selector, bool enabled) external override {
        _onlyEmergency();
        backupBypassSelector[selector] = enabled;
        emit BackupSelectorBypassUpdated(selector, enabled, msg.sender);
    }

    function executeTransaction(MERAWalletTypes.Call[] calldata calls) external payable override {
        MERAWalletTypes.Role callerRole = _requireController();
        MERAWalletTypes.Call[] memory memoryCalls = calls;

        _validateCalls(memoryCalls);

        bytes32 operationId = _computeOperationId(memoryCalls);
        uint256 requiredDelay = _getRequiredDelay(callerRole, memoryCalls);

        require(
            requiredDelay == 0 || _hasBypass(callerRole, memoryCalls),
            TimelockRequired(requiredDelay)
        );

        _beforeExecute(memoryCalls, operationId);
        _validateExtensionPolicy(memoryCalls);
        _executeCalls(memoryCalls);
        _afterExecute(memoryCalls, operationId);

        emit ImmediateTransactionExecuted(operationId, msg.sender);
    }

    function proposeTransaction(MERAWalletTypes.Call[] calldata calls) external override returns (bytes32 operationId) {
        MERAWalletTypes.Role callerRole = _requireController();
        MERAWalletTypes.Call[] memory memoryCalls = calls;

        _validateCalls(memoryCalls);

        operationId = _computeOperationId(memoryCalls);
        uint256 requiredDelay = _getRequiredDelay(callerRole, memoryCalls);
        require(requiredDelay != 0, ZeroDelayNotProposable());

        require(
            operations[operationId].status != MERAWalletTypes.OperationStatus.Pending,
            OperationAlreadyPending(operationId)
        );

        uint256 executeAfter = block.timestamp + requiredDelay;
        operations[operationId] = MERAWalletTypes.PendingOperation({
            creator: msg.sender,
            creatorRole: callerRole,
            createdAt: uint64(block.timestamp),
            executeAfter: uint64(executeAfter),
            status: MERAWalletTypes.OperationStatus.Pending
        });

        _beforePropose(memoryCalls, operationId);

        emit TransactionProposed(operationId, msg.sender, callerRole, executeAfter, requiredDelay);
    }

    function executePending(MERAWalletTypes.Call[] calldata calls) external payable override {
        _requireController();
        MERAWalletTypes.Call[] memory memoryCalls = calls;
        _validateCalls(memoryCalls);

        bytes32 operationId = _computeOperationId(memoryCalls);
        MERAWalletTypes.PendingOperation storage operation = operations[operationId];

        require(operation.status == MERAWalletTypes.OperationStatus.Pending, OperationNotPending(operationId));
        require(
            block.timestamp >= operation.executeAfter,
            TimelockNotExpired(operation.executeAfter, block.timestamp)
        );

        operation.status = MERAWalletTypes.OperationStatus.Executed;

        _beforeExecute(memoryCalls, operationId);
        _validateExtensionPolicy(memoryCalls);
        _executeCalls(memoryCalls);
        _afterExecute(memoryCalls, operationId);

        emit PendingTransactionExecuted(operationId, msg.sender);
    }

    function cancelPending(bytes32 operationId) external override {
        MERAWalletTypes.Role callerRole = _requireController();
        MERAWalletTypes.PendingOperation storage operation = operations[operationId];
        require(operation.status == MERAWalletTypes.OperationStatus.Pending, OperationNotPending(operationId));

        bool isCreator = operation.creator == msg.sender;
        require(
            isCreator || _canOverrideRole(callerRole, operation.creatorRole),
            CannotCancelOperation(operationId)
        );

        operation.status = MERAWalletTypes.OperationStatus.Cancelled;
        emit PendingTransactionCancelled(operationId, msg.sender);
    }

    function getOperationId(MERAWalletTypes.Call[] calldata calls) external view override returns (bytes32) {
        MERAWalletTypes.Call[] memory memoryCalls = calls;
        _validateCalls(memoryCalls);
        return _computeOperationId(memoryCalls);
    }

    function getRequiredDelay(MERAWalletTypes.Call[] calldata calls) external view override returns (uint256) {
        MERAWalletTypes.Role callerRole = _roleOf(msg.sender);
        require(callerRole != MERAWalletTypes.Role.None, Unauthorized());

        MERAWalletTypes.Call[] memory memoryCalls = calls;
        _validateCalls(memoryCalls);
        return _getRequiredDelay(callerRole, memoryCalls);
    }

    function set1271Signer(address signer) external override {
        _onlyEmergency();
        _set1271Signer(signer);
    }

    function isValidSignature(bytes32 hash, bytes calldata signature) external view override returns (bytes4) {
        address recovered = _recoverSigner(hash, signature);
        if (recovered == address(0)) {
            return MERAWalletConstants.EIP1271_INVALID;
        }

        if (eip1271Signer != address(0)) {
            return recovered == eip1271Signer ? MERAWalletConstants.EIP1271_MAGICVALUE : MERAWalletConstants.EIP1271_INVALID;
        }

        return MERAWalletConstants.EIP1271_INVALID;
    }

    function _executeSingleCall(address target, uint256 value, bytes memory data) internal {
        MERAWalletTypes.Call[] memory calls = new MERAWalletTypes.Call[](1);
        calls[0] = MERAWalletTypes.Call({target: target, value: value, data: data});

        MERAWalletTypes.Role callerRole = _requireController();
        _validateCalls(calls);

        bytes32 operationId = _computeOperationId(calls);
        uint256 requiredDelay = _getRequiredDelay(callerRole, calls);
        require(
            requiredDelay == 0 || _hasBypass(callerRole, calls),
            TimelockRequired(requiredDelay)
        );

        _beforeExecute(calls, operationId);
        _validateExtensionPolicy(calls);
        _executeCalls(calls);
        _afterExecute(calls, operationId);

        emit ImmediateTransactionExecuted(operationId, msg.sender);
    }

    function _validateCalls(MERAWalletTypes.Call[] memory calls) internal pure {
        require(calls.length > 0, EmptyCalls());
    }

    function _computeOperationId(MERAWalletTypes.Call[] memory calls) internal view returns (bytes32) {
        return keccak256(abi.encode(block.chainid, address(this), calls));
    }

    function _getRequiredDelay(MERAWalletTypes.Role callerRole, MERAWalletTypes.Call[] memory calls)
        internal
        view
        returns (uint256 requiredDelay)
    {
        if (callerRole == MERAWalletTypes.Role.Emergency) {
            return 0;
        }

        uint256 callsLength = calls.length;
        for (uint256 i = 0; i < callsLength; ) {
            uint256 callDelay = _getCallDelay(calls[i]);
            if (callDelay > requiredDelay) {
                requiredDelay = callDelay;
            }
            unchecked {
                ++i;
            }
        }
    }

    function _getCallDelay(MERAWalletTypes.Call memory callData) internal view returns (uint256) {
        uint256 delay = globalTimelock;
        uint256 targetDelay = timelockByTarget[callData.target];
        if (targetDelay > delay) {
            delay = targetDelay;
        }

        bytes4 selector = _extractSelector(callData.data);
        uint256 selectorDelay = timelockBySelector[selector];
        if (selectorDelay > delay) {
            delay = selectorDelay;
        }

        return delay;
    }

    function _hasBypass(MERAWalletTypes.Role callerRole, MERAWalletTypes.Call[] memory calls) internal view returns (bool) {
        if (callerRole == MERAWalletTypes.Role.Emergency) {
            return true;
        }
        if (callerRole != MERAWalletTypes.Role.Backup) {
            return false;
        }

        uint256 callsLength = calls.length;
        for (uint256 i = 0; i < callsLength; ) {
            MERAWalletTypes.Call memory callData = calls[i];
            bytes4 selector = _extractSelector(callData.data);
            bool isBypassed = backupBypassTarget[callData.target] || backupBypassSelector[selector];
            if (!isBypassed) {
                return false;
            }
            unchecked {
                ++i;
            }
        }

        return true;
    }

    function _executeCalls(MERAWalletTypes.Call[] memory calls) internal {
        uint256 callsLength = calls.length;
        for (uint256 i = 0; i < callsLength; ) {
            MERAWalletTypes.Call memory callData = calls[i];
            (bool success, bytes memory result) = callData.target.call{value: callData.value}(callData.data);
            require(success, CallExecutionFailed(i, result));
            unchecked {
                ++i;
            }
        }
    }

    function _set1271Signer(address signer) internal {
        require(
            signer == address(0) || signer == primary || signer == backup || signer == emergency,
            InvalidSigner()
        );

        address previousSigner = eip1271Signer;
        eip1271Signer = signer;
        emit EIP1271SignerUpdated(previousSigner, signer, msg.sender);
    }

    function _extractSelector(bytes memory data) internal pure returns (bytes4 selector) {
        if (data.length < 4) {
            return bytes4(0);
        }
        // The first 4 bytes in calldata-encoded call data are always the function selector.
        assembly {
            selector := mload(add(data, 32))
        }
    }

    /// @dev OpenZeppelin ECDSA on calldata; zero address on invalid signature (no revert, for EIP-1271).
    function _recoverSigner(bytes32 hash, bytes calldata signature) internal pure returns (address) {
        (address recovered, ECDSA.RecoverError err, ) = ECDSA.tryRecoverCalldata(hash, signature);
        if (err != ECDSA.RecoverError.NoError) {
            return address(0);
        }
        return recovered;
    }

    function _requireController() internal view returns (MERAWalletTypes.Role role) {
        role = _roleOf(msg.sender);
        require(role != MERAWalletTypes.Role.None, Unauthorized());
    }

    function _onlyEmergency() internal view {
        require(msg.sender == emergency, NotEmergency());
    }

    function _roleOf(address account) internal view returns (MERAWalletTypes.Role) {
        if (account == primary) {
            return MERAWalletTypes.Role.Primary;
        }
        if (account == backup) {
            return MERAWalletTypes.Role.Backup;
        }
        if (account == emergency) {
            return MERAWalletTypes.Role.Emergency;
        }
        return MERAWalletTypes.Role.None;
    }

    function _canOverrideRole(MERAWalletTypes.Role callerRole, MERAWalletTypes.Role creatorRole) internal pure returns (bool) {
        return (callerRole == MERAWalletTypes.Role.Backup && creatorRole == MERAWalletTypes.Role.Primary)
            || (callerRole == MERAWalletTypes.Role.Emergency
                && (creatorRole == MERAWalletTypes.Role.Primary || creatorRole == MERAWalletTypes.Role.Backup));
    }

    function _beforePropose(MERAWalletTypes.Call[] memory calls, bytes32 operationId) internal virtual {}

    function _beforeExecute(MERAWalletTypes.Call[] memory calls, bytes32 operationId) internal virtual {}

    function _afterExecute(MERAWalletTypes.Call[] memory calls, bytes32 operationId) internal virtual {}

    function _validateExtensionPolicy(MERAWalletTypes.Call[] memory calls) internal view virtual {}
}
