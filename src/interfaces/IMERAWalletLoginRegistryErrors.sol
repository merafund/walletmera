// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.34;

/// @notice Custom errors for MERAWalletLoginRegistry.
interface IMERAWalletLoginRegistryErrors {
    error EmptyLogin();
    error InvalidAddress();
    error InvalidPayment();
    error InvalidLoginLength();
    error InvalidLoginCharacter();
    error InvalidHyphen();
    error UnauthorizedFactory();
    error LoginAlreadyRegistered();
    error LoginNotOwned();
    error AddressAlreadyHasLogin();
    error ReferrerLoginNotRegistered();
    error SelfReferral();
    error CommitmentAlreadyExists();
    error CommitmentNotFound();
    error CommitmentTooNew();
    error CommitmentExpired();
    error SameWallet();
    error LoginMigrationAlreadyPending();
    error LoginMigrationNotFound();
    error LoginMigrationNotConfirmingWallet();
    error LoginMigrationStale();
    error LoginMigrationGuardianEmergencyMismatch();
    error InvalidBaseLoginPrice();
    error InvalidLoginPriceMultiplier();
    error NothingToWithdraw();
    error WithdrawFailed();
    error AuthorizationVerifierNotSet();
}
