// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.34;

/// @notice Events emitted by MERAWalletLoginRegistry.
interface IMERAWalletLoginRegistryEvents {
    /// @notice Emitted when a factory is authorized.
    event FactoryAdded(address indexed factory);
    /// @notice Emitted when the authorization verifier changes.
    event AuthorizationVerifierUpdated(address indexed previousVerifier, address indexed newVerifier);
    /// @notice Emitted when a registration commitment is stored.
    event LoginCommitmentMade(bytes32 indexed commitment, uint256 committedAt);
    /// @notice Emitted when a login is registered for a wallet.
    event LoginRegistered(bytes32 indexed loginHash, string login, address indexed wallet, address indexed factory);
    /// @notice Emitted when a referrer is recorded for a login.
    event LoginReferralRecorded(bytes32 indexed loginHash, bytes32 indexed referrerLoginHash, string referrerLogin);
    /// @notice Emitted when login ownership moves between wallets.
    event LoginTransferred(
        bytes32 indexed loginHash, string login, address indexed previousWallet, address indexed newWallet
    );
    /// @notice Emitted when login migration is requested.
    event LoginMigrationRequested(
        bytes32 indexed oldLoginHash,
        string oldLogin,
        bytes32 indexed newLoginHash,
        string newLogin,
        address indexed previousWallet,
        address newWallet
    );
    /// @notice Emitted when login migration is cancelled.
    event LoginMigrationCancelled(
        bytes32 indexed oldLoginHash,
        string oldLogin,
        bytes32 indexed newLoginHash,
        address indexed previousWallet,
        address newWallet
    );
    /// @notice Emitted when login migration is confirmed.
    event LoginMigrationConfirmed(
        bytes32 indexed oldLoginHash,
        string oldLogin,
        bytes32 indexed newLoginHash,
        string newLogin,
        address indexed previousWallet,
        address newWallet
    );
    /// @notice Emitted when the base paid-login price changes.
    event BaseLoginPriceUpdated(uint256 previousPrice, uint256 newPrice);
    /// @notice Emitted when the short-login multiplier changes.
    event LoginPriceMultiplierUpdated(uint256 previousMultiplier, uint256 newMultiplier);
    /// @notice Emitted when collected ETH is withdrawn.
    event EthWithdrawn(address indexed to, uint256 amount);
}
