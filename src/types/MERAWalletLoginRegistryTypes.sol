// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.34;

/// @notice Structs used by MERAWalletLoginRegistry (must stay ABI-compatible if field order changes).
library MERAWalletLoginRegistryTypes {
    struct PendingLoginMigration {
        address previousWallet;
        address newWallet;
        bytes32 newLoginHash;
    }

    struct RegistrationValidationParams {
        address registry;
        address factory;
        bytes32 loginHash;
        string login;
        address wallet;
        uint256 deadline;
        bytes authorization;
    }
}
