// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.34;

/// @notice Custom errors for BaseMERAWallet and extensions.
interface IBaseMERAWalletErrors {
    error InvalidAddress();
    error InvalidSigner();
    error EmptyCalls();
    error InvalidRole();
    error Unauthorized();
    error NotAllowedRoleChange();
    error NotEmergency();
    error ZeroDelayNotProposable();
    error TimelockRequired(uint256 requiredDelay);
    error OperationAlreadyPending(bytes32 operationId);
    error OperationNotPending(bytes32 operationId);
    error TimelockNotExpired(uint256 executeAfter, uint256 currentTime);
    error CannotCancelOperation(bytes32 operationId);
    error CallExecutionFailed(uint256 index, bytes revertData);
}
