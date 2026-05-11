// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.34;

/// @notice Structs used by MERAWalletLoginRegistry (must stay ABI-compatible if field order changes).
library MERAWalletLoginRegistryTypes {
    /// @notice Pending login migration from an old wallet/login pair to a new wallet/login pair.
    struct PendingLoginMigration {
        /// @notice Wallet currently owning the old login.
        address previousWallet;
        /// @notice Wallet that must confirm the migration.
        address newWallet;
        /// @notice Login hash that will be assigned to `newWallet`.
        bytes32 newLoginHash;
    }

    /// @notice Inputs passed to the optional login authorization verifier.
    struct RegistrationValidationParams {
        /// @notice Registry contract performing the validation.
        address registry;
        /// @notice Factory registering the wallet.
        address factory;
        /// @notice Keccak256 hash of the login string.
        bytes32 loginHash;
        /// @notice Plain-text login being registered.
        string login;
        /// @notice Wallet address being registered.
        address wallet;
        /// @notice Authorization deadline supplied by the caller.
        uint256 deadline;
        /// @notice Opaque authorization payload consumed by the verifier.
        bytes authorization;
    }
}
