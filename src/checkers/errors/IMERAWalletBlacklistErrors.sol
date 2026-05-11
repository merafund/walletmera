// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.34;

/// @notice Custom errors used by blacklist checkers.
interface IMERAWalletBlacklistErrors {
    /// @notice Address argument is invalid.
    error BlacklistInvalidAddress();
    /// @notice Caller is not the emergency authority.
    error BlacklistNotEmergency();
    /// @notice Caller is not authorized to apply blacklist config.
    error BlacklistConfigNotAuthorized();
    /// @notice Target address is blocked.
    error TargetBlocked(address target, uint256 index);
}
