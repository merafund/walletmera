// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.34;

import {MERAWalletConstants} from "../constants/MERAWalletConstants.sol";
import {MERAWalletTypes} from "../types/MERAWalletTypes.sol";
import {BaseMERAWallet} from "../BaseMERAWallet.sol";

/// @notice Memory-built `Call[]` helpers for extensions (ERC20 / native convenience entrypoints).
abstract contract MERAWalletMemoryBatches is BaseMERAWallet {
    /// @dev First 4 bytes of ABI-encoded calldata (`bytes memory` has no slice operator in Solidity).
    function _extractSelectorFromMemoryBytes(bytes memory data) internal pure returns (bytes4 selector) {
        if (data.length < MERAWalletConstants.FUNCTION_SELECTOR_LENGTH) {
            return bytes4(0);
        }
        assembly ("memory-safe") {
            selector := mload(add(data, 32))
        }
    }

    function _getCallDelayForPolicyRoleFromMemoryData(
        MERAWalletTypes.Role policyRole,
        address target,
        bytes memory data
    ) internal view returns (uint256) {
        return _getCallDelayForPolicyRoleFromSelector(policyRole, target, _extractSelectorFromMemoryBytes(data));
    }

    function _isEmergencyTimelockExemptSelfCallWithCallMemory(MERAWalletTypes.Call memory callData)
        internal
        view
        returns (bool)
    {
        if (callData.target != address(this)) {
            return false;
        }
        return _isEmergencyConfigSelector(_extractSelectorFromMemoryBytes(callData.data));
    }

    function _getCallDelayWithCallMemory(MERAWalletTypes.Role callerRole, MERAWalletTypes.Call memory callData)
        internal
        view
        returns (uint256)
    {
        if (callerRole == MERAWalletTypes.Role.Emergency) {
            if (_isEmergencyTimelockExemptSelfCallWithCallMemory(callData)) {
                return 0;
            }
        }
        return _getCallDelayForPolicyRoleFromMemoryData(callerRole, callData.target, callData.data);
    }

    /// @dev Must stay aligned with {BaseMERAWallet._validateCalls} (calldata batch path).
    function _validateCallsMemory(MERAWalletTypes.Call[] memory calls) internal view {
        require(calls.length > 0, EmptyCalls());
        require(
            calls.length <= MERAWalletConstants.MAX_CALLS_PER_BATCH,
            TooManyCalls(calls.length, MERAWalletConstants.MAX_CALLS_PER_BATCH)
        );
        uint256 n = calls.length;
        for (uint256 i = 0; i < n;) {
            if (calls[i].target != address(this)) {
                address checker = calls[i].checker;
                require(whitelistOptionalChecker[checker].allowed, OptionalCheckerNotAllowed(checker, i));
            }
            unchecked {
                ++i;
            }
        }
    }

    /// @dev Must stay aligned with {BaseMERAWallet._computeOperationId}.
    function _computeOperationIdMemory(MERAWalletTypes.Call[] memory calls, uint256 salt)
        internal
        view
        returns (bytes32 id)
    {
        bytes memory preimage = abi.encode(block.chainid, address(this), calls, salt);
        assembly ("memory-safe") {
            id := keccak256(add(preimage, 32), mload(preimage))
        }
    }

    /// @dev Must stay aligned with {BaseMERAWallet._getRequiredDelay} (uses per-call memory delay helpers on base).
    function _getRequiredDelayMemory(MERAWalletTypes.Role callerRole, MERAWalletTypes.Call[] memory calls)
        internal
        view
        returns (uint256 requiredDelay)
    {
        uint256 callsLength = calls.length;
        for (uint256 i = 0; i < callsLength;) {
            uint256 callDelay = _getCallDelayWithCallMemory(callerRole, calls[i]);
            if (callDelay > requiredDelay) {
                requiredDelay = callDelay;
            }
            unchecked {
                ++i;
            }
        }
    }

    function _proposeTransactionFromMemory(MERAWalletTypes.Call[] memory memoryCalls, uint256 salt)
        internal
        whenControllerCoreUnfrozen
        returns (bytes32 operationId, MERAWalletTypes.Role callerRole, uint256 executeAfter, uint256 requiredDelay)
    {
        callerRole = _effectiveCoreRole();

        _validateCallsMemory(memoryCalls);

        operationId = _computeOperationIdMemory(memoryCalls, salt);
        requiredDelay = _getRequiredDelayMemory(callerRole, memoryCalls);
        require(requiredDelay != 0, ZeroDelayNotProposable());

        MERAWalletTypes.OperationStatus existing = _operations[operationId].status;
        require(existing == MERAWalletTypes.OperationStatus.None, OperationAlreadyUsed(operationId));

        executeAfter = block.timestamp + requiredDelay;
        _operations[operationId] = MERAWalletTypes.PendingOperation({
            creator: _effectiveCaller(),
            creatorRole: callerRole,
            createdAt: uint64(block.timestamp),
            executeAfter: uint64(executeAfter),
            salt: salt,
            status: MERAWalletTypes.OperationStatus.Pending
        });

        _beforeProposeWithCallsMemory(memoryCalls, operationId);

        emit TransactionProposed(operationId, salt, _effectiveCaller(), callerRole, executeAfter, requiredDelay);
    }

    function _executePendingFromMemory(
        MERAWalletTypes.Call[] memory memoryCalls,
        uint256 salt,
        address[] memory executorWhitelist
    ) internal {
        _validateCallsMemory(memoryCalls);

        bytes32 operationId = _computeOperationIdMemory(memoryCalls, salt);
        MERAWalletTypes.PendingOperation storage operation = _operations[operationId];
        MERAWalletTypes.RelayOperation storage relayOperation = _relayOperations[operationId];

        require(operation.status == MERAWalletTypes.OperationStatus.Pending, OperationNotPending(operationId));
        require(block.timestamp >= operation.executeAfter, TimelockNotExpired(operation.executeAfter, block.timestamp));
        _requireRelayExecutionNotExpired(relayOperation);

        if (relayOperation.relayPolicy == MERAWalletTypes.RelayExecutorPolicy.CoreExecute) {
            require(executorWhitelist.length == 0, InvalidExecutorWhitelist());
            _requireControllerCoreUnfrozen();
        } else {
            require(!_isCoreController(msg.sender), CoreExecutorNotAllowed(msg.sender));
            _validateRelayExecutor(relayOperation, executorWhitelist);
        }

        operation.status = MERAWalletTypes.OperationStatus.Executed;

        _executeCallsWithHooksWithCallsMemory(memoryCalls, operationId, operation.creator, operation.creatorRole);
        _payoutRelayReward(relayOperation);

        emit PendingTransactionExecuted(operationId, salt, msg.sender);
    }

    function _executeImmediateFromCalls(MERAWalletTypes.Call[] memory calls, uint256 salt)
        internal
        whenLifeAlive
        whenControllerCoreUnfrozen
    {
        _validateCallsMemory(calls);

        bytes32 operationId = _computeOperationIdMemory(calls, salt);
        MERAWalletTypes.Role callerRole = _effectiveCoreRole();
        uint256 requiredDelay = _getRequiredDelayMemory(callerRole, calls);
        require(requiredDelay == 0, TimelockRequired(requiredDelay));

        _executeCallsWithHooksWithCallsMemory(calls, operationId, _effectiveCaller(), callerRole);

        emit ImmediateTransactionExecuted(operationId, salt, msg.sender);
    }

    function _executeSingleCall(
        address target,
        uint256 value,
        bytes memory data,
        address checker,
        bytes memory checkerData,
        uint256 salt
    ) internal {
        MERAWalletTypes.Call[] memory calls = new MERAWalletTypes.Call[](1);
        calls[0] = MERAWalletTypes.Call({
            target: target, value: value, data: data, checker: checker, checkerData: checkerData
        });
        _executeImmediateFromCalls(calls, salt);
    }

    /// @dev Copies dynamic calldata bytes into memory for a single-call batch (one allocation).
    function _bytesCalldataToMemory(bytes calldata data) internal pure returns (bytes memory) {
        uint256 len = data.length;
        bytes memory out = new bytes(len);
        for (uint256 i = 0; i < len;) {
            out[i] = data[i];
            unchecked {
                ++i;
            }
        }
        return out;
    }

    /// @dev Fills `calls[0]` for a single immediate or timelock helper path.
    function _setSingleCallMemory(
        MERAWalletTypes.Call[] memory calls,
        address target,
        uint256 value,
        bytes memory data,
        address checker,
        bytes memory checkerData
    ) internal pure {
        calls[0] = MERAWalletTypes.Call({
            target: target, value: value, data: data, checker: checker, checkerData: checkerData
        });
    }

    /// @dev Single-call immediate execution with calldata payload (no optional checker).
    function _executeSingleCallCalldata(address target, uint256 value, bytes calldata data, uint256 salt) internal {
        MERAWalletTypes.Call[] memory calls = new MERAWalletTypes.Call[](1);
        _setSingleCallMemory(calls, target, value, _bytesCalldataToMemory(data), address(0), new bytes(0));
        _executeImmediateFromCalls(calls, salt);
    }

    /// @dev Single-call immediate execution with calldata payload and optional checker data.
    function _executeSingleCallCalldata(
        address target,
        uint256 value,
        bytes calldata data,
        address checker,
        bytes calldata checkerData,
        uint256 salt
    ) internal {
        bytes memory checkerDataMem = checker == address(0) ? new bytes(0) : _bytesCalldataToMemory(checkerData);
        MERAWalletTypes.Call[] memory calls = new MERAWalletTypes.Call[](1);
        _setSingleCallMemory(calls, target, value, _bytesCalldataToMemory(data), checker, checkerDataMem);
        _executeImmediateFromCalls(calls, salt);
    }

    /// @dev Single-call propose built from memory `data` (e.g. ERC20 ABI payload).
    function _proposeSingleCallMemory(
        address target,
        uint256 value,
        bytes memory data,
        address checker,
        bytes memory checkerDataMem,
        uint256 salt
    ) internal returns (bytes32 operationId) {
        MERAWalletTypes.Call[] memory calls = new MERAWalletTypes.Call[](1);
        _setSingleCallMemory(calls, target, value, data, checker, checkerDataMem);
        (operationId,,,) = _proposeTransactionFromMemory(calls, salt);
    }

    /// @dev Single-call propose with calldata checker payload.
    function _proposeSingleCallCalldata(
        address target,
        uint256 value,
        bytes calldata data,
        address checker,
        bytes calldata checkerData,
        uint256 salt
    ) internal returns (bytes32 operationId) {
        bytes memory checkerDataMem = checker == address(0) ? new bytes(0) : _bytesCalldataToMemory(checkerData);
        MERAWalletTypes.Call[] memory calls = new MERAWalletTypes.Call[](1);
        _setSingleCallMemory(calls, target, value, _bytesCalldataToMemory(data), checker, checkerDataMem);
        (operationId,,,) = _proposeTransactionFromMemory(calls, salt);
    }

    /// @dev Single-call pending execution built from memory `data`.
    function _executePendingSingleCallMemory(
        address target,
        uint256 value,
        bytes memory data,
        address checker,
        bytes memory checkerDataMem,
        uint256 salt
    ) internal {
        MERAWalletTypes.Call[] memory calls = new MERAWalletTypes.Call[](1);
        _setSingleCallMemory(calls, target, value, data, checker, checkerDataMem);
        address[] memory empty = new address[](0);
        _executePendingFromMemory(calls, salt, empty);
    }

    /// @dev Single-call pending execution with calldata checker payload.
    function _executePendingSingleCallCalldata(
        address target,
        uint256 value,
        bytes calldata data,
        address checker,
        bytes calldata checkerData,
        uint256 salt
    ) internal {
        bytes memory checkerDataMem = checker == address(0) ? new bytes(0) : _bytesCalldataToMemory(checkerData);
        MERAWalletTypes.Call[] memory calls = new MERAWalletTypes.Call[](1);
        _setSingleCallMemory(calls, target, value, _bytesCalldataToMemory(data), checker, checkerDataMem);
        address[] memory empty = new address[](0);
        _executePendingFromMemory(calls, salt, empty);
    }
}
