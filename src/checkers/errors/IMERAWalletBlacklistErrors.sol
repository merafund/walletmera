// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.34;

/// @notice Custom errors used by blacklist checkers.
interface IMERAWalletBlacklistErrors {
    error BlacklistInvalidAddress();
    error BlacklistNotEmergency();
    error BlacklistConfigNotAuthorized();
    error TargetBlocked(address target, uint256 index);
}
