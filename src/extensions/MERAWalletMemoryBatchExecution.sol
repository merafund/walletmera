// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.34;

import {MERAWalletTypes} from "../types/MERAWalletTypes.sol";
import {BaseMERAWallet} from "../BaseMERAWallet.sol";

/// @notice Execution helpers for memory-built `Call[]` batches (used by {MERAWalletMemoryBatches} extensions).
abstract contract MERAWalletMemoryBatchExecution is BaseMERAWallet {
    /// @notice Hook before proposing extension batches built in memory; default no-op.
    function _beforeProposeWithCallsMemory(MERAWalletTypes.Call[] memory calls, bytes32 operationId) internal virtual {}

    /// @notice Memory-batch equivalent of {_beforeExecute}; override in extensions if needed.
    function _beforeExecuteWithCallMemory(MERAWalletTypes.Call memory callData, bytes32 operationId, uint256 callId)
        internal
        virtual
    {
        _invokeBeforeRequiredCheckersWithCallMemory(callData, operationId, callId);
        _invokeBeforeOptionalCheckerWithCallMemory(callData, operationId, callId);
    }

    /// @notice Memory-batch equivalent of {_afterExecute}; override in extensions if needed.
    function _afterExecuteWithCallMemory(MERAWalletTypes.Call memory callData, bytes32 operationId, uint256 callId)
        internal
        virtual
    {
        _invokeAfterRequiredCheckersWithCallMemory(callData, operationId, callId);
        _invokeAfterOptionalCheckerWithCallMemory(callData, operationId, callId);
    }

    /// @notice Executes memory-built batches with the same hook flow as calldata execution.
    function _executeCallsWithHooksWithCallsMemory(
        MERAWalletTypes.Call[] memory calls,
        bytes32 operationId,
        MERAWalletTypes.Role contextRole
    ) internal {
        uint256 callsLength = calls.length;
        for (uint256 i = 0; i < callsLength;) {
            MERAWalletTypes.Call memory callData = calls[i];
            _beforeExecuteWithCallMemory(callData, operationId, i);
            (bool success, bytes memory result) = _callWithExecutionContextMemory(callData, contextRole);
            require(success, CallExecutionFailed(i, result));
            _afterExecuteWithCallMemory(callData, operationId, i);
            unchecked {
                ++i;
            }
        }
    }

    /// @notice Executes `callData` while setting transient execution context for self-calls.
    function _callWithExecutionContextMemory(MERAWalletTypes.Call memory callData, MERAWalletTypes.Role contextRole)
        internal
        returns (bool success, bytes memory result)
    {
        if (callData.target != address(this)) {
            return callData.target.call{value: callData.value}(callData.data);
        }

        _storeExecutionContext(contextRole);
        (success, result) = callData.target.call{value: callData.value}(callData.data);
        _clearExecutionContext();
    }
}
