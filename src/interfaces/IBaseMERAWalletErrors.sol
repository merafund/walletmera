// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.34;

import {MERAWalletTypes} from "../types/MERAWalletTypes.sol";

/// @notice Custom errors for BaseMERAWallet and extensions.
interface IBaseMERAWalletErrors {
    error InvalidAddress();
    error InvalidCheckerAddress();
    error InvalidSigner();
    error EmptyCalls();
    error InvalidRole();
    error Unauthorized();
    error NotAllowedRoleChange();
    error NotEmergency();
    error ZeroDelayNotProposable();
    error TimelockRequired(uint256 requiredDelay);
    error CallPathForbiddenForRole(MERAWalletTypes.Role role);
    error OperationAlreadyPending(bytes32 operationId);
    error OperationNotPending(bytes32 operationId);
    error TimelockNotExpired(uint256 executeAfter, uint256 currentTime);
    error CannotCancelOperation(bytes32 operationId);
    error CancelPendingPrimaryOnly();
    error OperationVetoed(bytes32 operationId);
    error OperationAlreadyVetoed(bytes32 operationId);
    error OperationNotVetoed(bytes32 operationId);
    error CallExecutionFailed(uint256 index, bytes revertData);
    error CheckerNotWhitelisted(address checker, uint256 callIndex);
    error NoopCheckerConfig();
    error NotCoreController();
    error AgentRemovalNotAuthorized();
    error NoopControllerAgent();
    /// @dev Core controller attempted an action while their role level is frozen.
    error RoleFrozen(MERAWalletTypes.Role role);
    /// @dev Caller is not allowed to change freeze flags (wrong role for this flag).
    error FreezeActionNotAuthorized();
}
