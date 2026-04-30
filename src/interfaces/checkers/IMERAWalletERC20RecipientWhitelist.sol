// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.34;

/// @notice ERC20 counterparty allowlist used by transfer and approve whitelist checkers.
interface IMERAWalletERC20RecipientWhitelist {
    function isRecipientAllowed(address recipient) external view returns (bool allowed);
}
