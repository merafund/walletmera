// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.34;

/// @notice Custom errors used by whitelist checkers.
interface IMERAWalletWhitelistErrors {
    error WhitelistInvalidAddress();
    error WhitelistNotEmergency();
    error TargetNotAllowed(address target, uint256 index);
}
