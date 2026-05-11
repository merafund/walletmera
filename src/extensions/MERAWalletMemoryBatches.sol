// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.34;

import {MERAWalletConstants} from "../constants/MERAWalletConstants.sol";
import {MERAWalletTypes} from "../types/MERAWalletTypes.sol";
import {MERAWalletMemoryBatchExecution} from "./MERAWalletMemoryBatchExecution.sol";

/// @notice Memory-built `Call[]` helpers for extensions (ERC20 / native convenience entrypoints).
abstract contract MERAWalletMemoryBatches is MERAWalletMemoryBatchExecution {
    /// @notice Extracts the first four bytes from ABI calldata held in memory.
    /// @dev `bytes memory` has no slice operator in Solidity.
    function _extractSelectorFromMemoryBytes(bytes memory data) internal pure returns (bytes4 selector) {
        if (data.length < MERAWalletConstants.FUNCTION_SELECTOR_LENGTH) {
            return bytes4(0);
        }
        assembly ("memory-safe") {
            selector := mload(add(data, 32))
        }
    }

    /// @notice Returns the call delay for a target and memory calldata payload.
    function _getCallDelayForPolicyRoleFromMemoryData(
        MERAWalletTypes.Role policyRole,
        address target,
        bytes memory data
    ) internal view returns (uint256) {
        return _getCallDelayForPolicyRoleFromSelector(policyRole, target, _extractSelectorFromMemoryBytes(data));
    }

    /// @notice Returns the call delay for a memory-built call.
    function _getCallDelayWithCallMemory(MERAWalletTypes.Role callerRole, MERAWalletTypes.Call memory callData)
        internal
        view
        returns (uint256)
    {
        return _getCallDelayForPolicyRoleFromMemoryData(callerRole, callData.target, callData.data);
    }

    /// @notice Validates a memory-built call batch.
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

    /// @notice Computes the operation id for a memory-built call batch.
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

    /// @notice Returns the maximum required delay for a memory-built call batch.
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

    /// @notice Stores a pending operation from a memory-built call batch.
    function _proposeTransactionFromMemory(MERAWalletTypes.Call[] memory memoryCalls, uint256 salt)
        internal
        whenControllerCoreAvailable
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
            creator: msg.sender,
            creatorRole: callerRole,
            createdAt: uint64(block.timestamp),
            executeAfter: uint64(executeAfter),
            salt: salt,
            status: MERAWalletTypes.OperationStatus.Pending
        });

        _beforeProposeWithCallsMemory(memoryCalls, operationId);

        emit TransactionProposed(operationId, salt, msg.sender, callerRole, executeAfter, requiredDelay);
    }

    /// @notice Executes a pending operation from a memory-built call batch.
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
            _requireControllerCoreAvailable();
        } else {
            require(!_isCoreController(msg.sender), CoreExecutorNotAllowed(msg.sender));
            _validateRelayExecutor(relayOperation, executorWhitelist);
        }

        operation.status = MERAWalletTypes.OperationStatus.Executed;

        _executeCallsWithHooksWithCallsMemory(memoryCalls, operationId, operation.creatorRole);
        _payoutRelayReward(relayOperation);

        emit PendingTransactionExecuted(operationId, salt, msg.sender);
    }

    /// @notice Executes a memory-built call batch immediately.
    function _executeImmediateFromCalls(MERAWalletTypes.Call[] memory calls, uint256 salt)
        internal
        whenLifeAlive
        whenControllerCoreAvailable
    {
        _validateCallsMemory(calls);

        bytes32 operationId = _computeOperationIdMemory(calls, salt);
        MERAWalletTypes.Role callerRole = _effectiveCoreRole();
        uint256 requiredDelay = _getRequiredDelayMemory(callerRole, calls);
        require(requiredDelay == 0, TimelockRequired(requiredDelay));

        _executeCallsWithHooksWithCallsMemory(calls, operationId, callerRole);

        emit ImmediateTransactionExecuted(operationId, salt, msg.sender);
    }

    /// @notice Executes a single memory-built call immediately.
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

    /// @notice Copies dynamic calldata bytes into memory for a single-call batch.
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

    /// @notice Fills `calls[0]` for a single immediate or timelock helper path.
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

    /// @notice Executes a single calldata payload immediately without an optional checker.
    function _executeSingleCallCalldata(address target, uint256 value, bytes calldata data, uint256 salt) internal {
        MERAWalletTypes.Call[] memory calls = new MERAWalletTypes.Call[](1);
        _setSingleCallMemory(calls, target, value, _bytesCalldataToMemory(data), address(0), new bytes(0));
        _executeImmediateFromCalls(calls, salt);
    }

    /// @notice Executes a single calldata payload immediately with optional checker data.
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

    /// @notice Proposes a single-call operation built from memory `data`.
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

    /// @notice Executes a pending single-call operation built from memory `data`.
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
}
