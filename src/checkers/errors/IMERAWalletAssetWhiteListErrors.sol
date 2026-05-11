// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.34;

/// @notice Custom errors for {MERAWalletAssetWhiteList}.
interface IMERAWalletAssetWhiteListErrors {
    /// @notice Asset address argument is invalid.
    error AssetWhitelistInvalidAddress();
    /// @notice Parallel update arrays have different lengths.
    error AssetWhitelistArrayLengthMismatch();
}
