// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.34;

/// @notice ERC20 counterparty allowlist used by transfer and approve whitelist checkers.
interface IMERAWalletERC20RecipientWhitelist {
    /// @notice Returns whether `recipient` is allowed by this whitelist or its fallback.
    /// @param recipient Account checked as transfer recipient or approve spender.
    /// @return allowed True when the account may be used as the ERC20 counterparty.
    function isRecipientAllowed(address recipient) external view returns (bool allowed);
}
