// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.34;

import {MERAWalletTypes} from "../types/MERAWalletTypes.sol";

/// @notice Custom errors for BaseMERAWallet and extensions.
interface IBaseMERAWalletErrors {
    error InvalidAddress();
    error InvalidCheckerAddress();
    error InvalidSigner();
    error EmptyCalls();
    error TooManyCalls(uint256 length, uint256 maxAllowed);
    error InvalidRole();
    error Unauthorized();
    error NotAllowedRoleChange();
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
    error CannotClearVeto(bytes32 operationId);
    error OperationAlreadyVetoed(bytes32 operationId);
    error OperationNotVetoed(bytes32 operationId);
    error InvalidRelayConfig();
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
    error NoopControllerAgent();
    /// @dev Core controller attempted an action while their role level is frozen.
    error RoleFrozen(MERAWalletTypes.Role role);
    /// @dev Caller is not allowed to change freeze flags (wrong role for this flag).
    error FreezeActionNotAuthorized();
    error NotLifeController();
    error LifeHeartbeatTimeoutZero();
    error LifeHeartbeatExpired(uint256 lastHeartbeatAt, uint256 timeout, uint256 currentTime);
    error EmergencyMustStayLifeController();
    error TooManyRequiredCheckers(uint256 length, uint256 maxAllowed);
    /// @dev Controller agents cannot veto a pending op created by the emergency role.
    error AgentCannotVetoEmergencyOperation();
    /// @dev Parallel calldata arrays for a batch setter had different lengths.
    error ArrayLengthMismatch(uint256 a, uint256 b);
}
