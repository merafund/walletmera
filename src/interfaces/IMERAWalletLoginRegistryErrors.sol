// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.34;

/// @notice Custom errors for MERAWalletLoginRegistry.
interface IMERAWalletLoginRegistryErrors {
    /// @notice Login string is empty.
    error EmptyLogin();
    /// @notice Address argument is invalid.
    error InvalidAddress();
    /// @notice ETH payment does not match the required price.
    error InvalidPayment();
    /// @notice Login length is outside allowed bounds.
    error InvalidLoginLength();
    /// @notice Login contains an unsupported character.
    error InvalidLoginCharacter();
    /// @notice Login hyphen placement is invalid.
    error InvalidHyphen();
    /// @notice Caller is not an authorized factory.
    error UnauthorizedFactory();
    /// @notice Login is already registered.
    error LoginAlreadyRegistered();
    /// @notice Caller or wallet does not own the requested login.
    error LoginNotOwned();
    /// @notice Wallet already has a registered login.
    error AddressAlreadyHasLogin();
    /// @notice Referrer login is not registered.
    error ReferrerLoginNotRegistered();
    /// @notice Referrer was already set.
    error ReferrerAlreadySet();
    /// @notice Login cannot refer itself.
    error SelfReferral();
    /// @notice Commitment already exists.
    error CommitmentAlreadyExists();
    /// @notice Commitment was not found.
    error CommitmentNotFound();
    /// @notice Commitment is younger than the minimum age.
    error CommitmentTooNew();
    /// @notice Commitment is older than the maximum age.
    error CommitmentExpired();
    /// @notice Migration target wallet must differ from the caller.
    error SameWallet();
    /// @notice Login migration is already pending.
    error LoginMigrationAlreadyPending();
    /// @notice Login migration was not found.
    error LoginMigrationNotFound();
    /// @notice Caller is not the wallet that requested migration.
    error LoginMigrationNotRequester();
    /// @notice Caller is not the wallet expected to confirm migration.
    error LoginMigrationNotConfirmingWallet();
    /// @notice Login migration state no longer matches registry ownership.
    error LoginMigrationStale();
    /// @notice Migrating wallets do not share guardian and emergency roles.
    error LoginMigrationGuardianEmergencyMismatch();
    /// @notice Base login price is outside allowed bounds.
    error InvalidBaseLoginPrice();
    /// @notice Login price multiplier is outside allowed bounds.
    error InvalidLoginPriceMultiplier();
    /// @notice No ETH is available to withdraw.
    error NothingToWithdraw();
    /// @notice ETH withdrawal failed.
    error WithdrawFailed();
    /// @notice Registration requires an authorization verifier, but none is set.
    error AuthorizationVerifierNotSet();
}
