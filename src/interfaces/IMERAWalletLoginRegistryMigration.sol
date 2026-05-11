// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.34;

/// @notice Login migration API for moving an existing login to a new wallet/login pair.
interface IMERAWalletLoginRegistryMigration {
    /// @notice Requests migration of `oldLogin` to `newLogin` and `newWallet`.
    /// @param oldLogin Login currently owned by the caller.
    /// @param newLogin Login that will be assigned after confirmation.
    /// @param newWallet Wallet that must confirm the migration.
    function requestLoginMigration(string calldata oldLogin, string calldata newLogin, address newWallet) external;
    /// @notice Confirms a pending login migration as the new wallet.
    /// @param oldLogin Existing login being migrated.
    function confirmLoginMigration(string calldata oldLogin) external;
}
