// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.34;

/// @notice Custom errors for {MERAWalletERC20RecipientWhitelist}.
interface IMERAWalletERC20RecipientWhitelistErrors {
    error RecipientWhitelistInvalidAddress();
    error RecipientWhitelistArrayLengthMismatch();
}
