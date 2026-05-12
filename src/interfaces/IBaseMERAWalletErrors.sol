// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.34;

import {MERAWalletTypes} from "../types/MERAWalletTypes.sol";

/// @notice Custom errors for BaseMERAWallet and extensions.
interface IBaseMERAWalletErrors {
    /// @notice Address argument is invalid.
    error InvalidAddress();
    /// @notice Wallet has already been initialized.
    error AlreadyInitialized();
    /// @notice Checker address is invalid.
    error InvalidCheckerAddress();
    /// @notice Signer address or recovered signer is invalid.
    error InvalidSigner();
    /// @notice Call batch is empty.
    error EmptyCalls();
    /// @notice Call batch length exceeds the maximum.
    error TooManyCalls(uint256 length, uint256 maxAllowed);
    /// @notice Role argument is invalid.
    error InvalidRole();
    /// @notice Caller is not authorized.
    error Unauthorized();
    /// @notice Caller cannot perform the requested role change.
    error NotAllowedRoleChange();
    /// @notice Caller role cannot update the target role timelock.
    /// @dev {setRoleTimelock}: caller core role rank must be >= target role rank (see {_roleRank}; Emergency highest).
    error RoleTimelockChangeNotAuthorized(MERAWalletTypes.Role callerRole, MERAWalletTypes.Role targetRole);
    /// @notice Caller role cannot replace the current EIP-1271 signer role.
    /// @dev {set1271Signer}: effective caller role rank must be >= current signer role rank (see {_roleRank}).
    error Set1271SignerNotAuthorized(MERAWalletTypes.Role callerRole, MERAWalletTypes.Role signerRole);
    /// @notice Caller must be the wallet contract itself.
    /// @dev Caller must be the wallet contract (delegatecall / batched self-call), not an EOA hitting `onlySelf` entrypoints.
    error NotSelf();
    /// @notice Caller is not the emergency controller.
    error NotEmergency();
    /// @notice Zero-delay calls must be executed immediately, not proposed.
    error ZeroDelayNotProposable();
    /// @notice Timelock delay exceeds the maximum.
    error TimelockDelayTooLarge(uint256 delay, uint256 maxDelay);
    /// @dev {setEmergencyAgentLifetime}: `lifetime` exceeds {MERAWalletConstants.MAX_EMERGENCY_AGENT_LIFETIME}.
    error EmergencyAgentLifetimeTooLarge(uint256 lifetime, uint256 maxLifetime);
    /// @notice Required timelock delay has not been satisfied by the selected path.
    error TimelockRequired(uint256 requiredDelay);
    /// @notice Role is forbidden from using this call path.
    error CallPathForbiddenForRole(MERAWalletTypes.Role role);
    /// @notice Operation is already pending.
    error OperationAlreadyPending(bytes32 operationId);
    /// @notice Operation id has already been used.
    error OperationAlreadyUsed(bytes32 operationId);
    /// @notice Operation is not pending.
    error OperationNotPending(bytes32 operationId);
    /// @notice Pending operation was invalidated by timestamp.
    error PendingTransactionInvalidated(bytes32 operationId);
    /// @notice Timelock has not expired.
    error TimelockNotExpired(uint256 executeAfter, uint256 currentTime);
    /// @notice Caller cannot cancel this operation.
    error CannotCancelOperation(bytes32 operationId);
    /// @notice Caller cannot veto this operation.
    error CannotVetoOperation(bytes32 operationId);
    /// @notice Caller cannot clear this veto.
    error CannotClearVeto(bytes32 operationId);
    /// @notice Operation is not vetoed.
    error OperationNotVetoed(bytes32 operationId);
    /// @notice Relay config is invalid.
    error InvalidRelayConfig();
    /// @dev {proposeTransactionWithRelay} requires a non-zero execution deadline.
    error RelayDeadlineRequired();
    /// @notice Relay deadline is before the operation timelock.
    error RelayDeadlineBeforeTimelock(uint64 relayExecuteBefore, uint256 executeAfter);
    /// @notice Relay execution deadline has expired.
    error RelayExecutionExpired(uint64 relayExecuteBefore, uint256 currentTime);
    /// @notice Relay reward is not allowed for this policy.
    error RelayRewardNotAllowed();
    /// @notice Caller is not allowed as relay executor.
    error RelayExecutorNotAllowed(address executor);
    /// @notice Core controller cannot use relay execution path.
    error CoreExecutorNotAllowed(address executor);
    /// @notice Executor whitelist is invalid for the selected policy.
    error InvalidExecutorWhitelist();
    /// @notice Relay reward transfer failed.
    error RelayRewardTransferFailed(address recipient, uint256 amount);
    /// @notice A call in the batch reverted.
    error CallExecutionFailed(uint256 index, bytes revertData);
    /// @notice Optional checker is not allowed for the call.
    error OptionalCheckerNotAllowed(address checker, uint256 callIndex);
    /// @notice Checker update would not change effective checker config.
    error NoopCheckerConfig();
    /// @notice Target-selector policy clear would not change state.
    error NoopTargetSelectorCallPolicy();
    /// @notice Caller is not a core controller.
    error NotCoreController();
    /// @notice Caller cannot remove or reduce this agent.
    error AgentRemovalNotAuthorized();
    /// @notice Agent update would not change state.
    error NoopAgent();
    /// @notice The wallet contract itself cannot be registered as an agent.
    error WalletCannotBeAgent();
    /// @notice The wallet contract itself cannot be assigned to a core controller role.
    error WalletCannotBeCoreRole();
    /// @notice Core controller attempted an action while their role level is frozen.
    error RoleFrozen(MERAWalletTypes.Role role);
    /// @notice Caller is not allowed to change freeze flags.
    error FreezeActionNotAuthorized();
    /// @notice Caller is not an enabled life controller.
    error NotLifeController();
    /// @notice Life heartbeat timeout cannot be zero when life control is enabled.
    error LifeHeartbeatTimeoutZero();
    /// @notice Life-control heartbeat has expired.
    error LifeHeartbeatExpired(uint256 lastHeartbeatAt, uint256 timeout, uint256 currentTime);
    /// @notice Emergency controller must remain a life controller.
    error EmergencyMustStayLifeController();
    /// @notice Required checker list exceeds the maximum.
    error TooManyRequiredCheckers(uint256 length, uint256 maxAllowed);
    /// @notice Agent lifetime has expired.
    error AgentExpired(address agent, uint256 expiresAt);
    /// @notice Parallel calldata arrays for a batch setter had different lengths.
    error ArrayLengthMismatch(uint256 a, uint256 b);
    /// @notice Caller is not allowed to enter safe mode.
    error SafeModeNotAuthorized();
    /// @notice Safe mode has already been used once and cannot be activated again.
    error SafeModeAlreadyUsed();
    /// @notice Requested duration is outside [SAFE_MODE_MIN_DURATION, SAFE_MODE_MAX_DURATION].
    error SafeModeDurationOutOfRange(uint256 duration);
    /// @notice Action is blocked while safe mode is active.
    error SafeModeActive(uint256 safeModeBefore);
    /// @notice resetSafeMode called but safe mode was never activated.
    error SafeModeNotUsed();
    /// @notice resetSafeMode called before the safe mode period has expired.
    error SafeModeStillActive(uint256 safeModeBefore);
    /// @notice executeMigrationTransaction called but migrationTarget is not set.
    error MigrationModeNotActive();
    /// @notice A migration call does not match allowed selectors or target.
    error MigrationCallNotAllowed(uint256 callIndex);
    /// @notice Migration batch call must not forward native value.
    error MigrationCallValueNotAllowed(uint256 callIndex);
}
