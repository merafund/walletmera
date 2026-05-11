// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.34;

/// @notice Custom errors used by whitelist checkers.
interface IMERAWalletWhitelistErrors {
    /// @notice Address argument is invalid.
    error WhitelistInvalidAddress();
    /// @notice Caller is not the emergency authority.
    error WhitelistNotEmergency();
    /// @notice Caller is not authorized to apply whitelist config.
    error WhitelistConfigNotAuthorized();
    /// @notice Target address is not allowed.
    error TargetNotAllowed(address target, uint256 index);
}
