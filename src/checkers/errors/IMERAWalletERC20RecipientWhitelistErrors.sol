// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.34;

/// @notice Custom errors for {MERAWalletERC20RecipientWhitelist}.
interface IMERAWalletERC20RecipientWhitelistErrors {
    /// @notice Recipient address argument is invalid.
    error RecipientWhitelistInvalidAddress();
    /// @notice Parallel update arrays have different lengths.
    error RecipientWhitelistArrayLengthMismatch();
}
