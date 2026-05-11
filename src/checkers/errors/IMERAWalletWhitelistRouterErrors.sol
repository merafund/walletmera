// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.34;

/// @notice Custom errors for {MERAWalletWhitelistRouter}.
interface IMERAWalletWhitelistRouterErrors {
    /// @notice Route hash is zero.
    error WhitelistRouterInvalidHash();
    /// @notice Parallel update arrays have different lengths.
    error WhitelistRouterArrayLengthMismatch();
}
