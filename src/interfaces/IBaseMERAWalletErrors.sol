// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.34;

import {MERAWalletTypes} from "../types/MERAWalletTypes.sol";

/// @notice Custom errors for BaseMERAWallet and extensions.
interface IBaseMERAWalletErrors {
    error InvalidAddress();
    error AlreadyInitialized();
    error InvalidCheckerAddress();
    error InvalidSigner();
    error EmptyCalls();
    error TooManyCalls(uint256 length, uint256 maxAllowed);
    error InvalidRole();
    error Unauthorized();
    error NotAllowedRoleChange();
    /// @dev Caller must be the wallet contract (delegatecall / batched self-call), not an EOA hitting `onlySelf` entrypoints.
    error NotSelf();
    error NotEmergency();
    error ZeroDelayNotProposable();
    error TimelockDelayTooLarge(uint256 delay, uint256 maxDelay);
    error TimelockRequired(uint256 requiredDelay);
    error CallPathForbiddenForRole(MERAWalletTypes.Role role);
    error OperationAlreadyPending(bytes32 operationId);
    error OperationAlreadyUsed(bytes32 operationId);
    error OperationNotPending(bytes32 operationId);
    error TimelockNotExpired(uint256 executeAfter, uint256 currentTime);
    error CannotCancelOperation(bytes32 operationId);
    error CannotVetoOperation(bytes32 operationId);
    error CannotClearVeto(bytes32 operationId);
    error OperationNotVetoed(bytes32 operationId);
    error InvalidRelayConfig();
    /// @dev {proposeTransactionWithRelay} requires a non-zero execution deadline.
    error RelayDeadlineRequired();
    error RelayDeadlineBeforeTimelock(uint64 relayExecuteBefore, uint256 executeAfter);
    error RelayExecutionExpired(uint64 relayExecuteBefore, uint256 currentTime);
    error RelayRewardNotAllowed();
    error RelayRewardRequired();
    error RelayExecutorNotAllowed(address executor);
    error CoreExecutorNotAllowed(address executor);
    error InvalidExecutorWhitelist();
    error RelayRewardTransferFailed(address recipient, uint256 amount);
    error CallExecutionFailed(uint256 index, bytes revertData);
    error OptionalCheckerNotAllowed(address checker, uint256 callIndex);
    error NoopCheckerConfig();
    error NoopTargetSelectorCallPolicy();
    error NotCoreController();
    error AgentRemovalNotAuthorized();
    error NoopAgent();
    /// @dev Core controller attempted an action while their role level is frozen.
    error RoleFrozen(MERAWalletTypes.Role role);
    /// @dev Caller is not allowed to change freeze flags (wrong role for this flag).
    error FreezeActionNotAuthorized();
    error NotLifeController();
    error LifeHeartbeatTimeoutZero();
    error LifeHeartbeatExpired(uint256 lastHeartbeatAt, uint256 timeout, uint256 currentTime);
    error EmergencyMustStayLifeController();
    error TooManyRequiredCheckers(uint256 length, uint256 maxAllowed);
    error AgentExpired(address agent, uint256 activeUntil);
    /// @dev Parallel calldata arrays for a batch setter had different lengths.
    error ArrayLengthMismatch(uint256 a, uint256 b);
    /// @dev Caller is not allowed to enter safe mode (not emergency or emergency-level agent).
    error SafeModeNotAuthorized();
    /// @dev Safe mode has already been used once and cannot be activated again.
    error SafeModeAlreadyUsed();
    /// @dev Requested duration is outside [SAFE_MODE_MIN_DURATION, SAFE_MODE_MAX_DURATION].
    error SafeModeDurationOutOfRange(uint256 duration);
    /// @dev Action is blocked while safe mode is active.
    error SafeModeActive(uint256 safeModeBefore);
    /// @dev resetSafeMode called but safe mode was never activated.
    error SafeModeNotUsed();
    /// @dev resetSafeMode called before the safe mode period has expired.
    error SafeModeStillActive(uint256 safeModeBefore);
    /// @dev executeMigrationTransaction called but migrationTarget is not set.
    error MigrationModeNotActive();
    /// @dev A call in the migration batch does not match allowed migration selectors or the recipient is not migrationTarget.
    error MigrationCallNotAllowed(uint256 callIndex);
}
