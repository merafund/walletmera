// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.34;

/// @notice Events emitted by MERAWalletLoginRegistry.
interface IMERAWalletLoginRegistryEvents {
    event FactoryAdded(address indexed factory);
    event AuthorizationVerifierUpdated(address indexed previousVerifier, address indexed newVerifier);
    event LoginCommitmentMade(bytes32 indexed commitment, uint256 committedAt);
    event LoginRegistered(bytes32 indexed loginHash, string login, address indexed wallet, address indexed factory);
    event LoginReferralRecorded(bytes32 indexed loginHash, bytes32 indexed referrerLoginHash, string referrerLogin);
    event LoginTransferred(
        bytes32 indexed loginHash, string login, address indexed previousWallet, address indexed newWallet
    );
    event LoginMigrationRequested(
        bytes32 indexed oldLoginHash,
        string oldLogin,
        bytes32 indexed newLoginHash,
        string newLogin,
        address indexed previousWallet,
        address newWallet
    );
    event LoginMigrationConfirmed(
        bytes32 indexed oldLoginHash,
        string oldLogin,
        bytes32 indexed newLoginHash,
        string newLogin,
        address indexed previousWallet,
        address newWallet
    );
    event BaseLoginPriceUpdated(uint256 previousPrice, uint256 newPrice);
    event LoginPriceMultiplierUpdated(uint256 previousMultiplier, uint256 newMultiplier);
    event EthWithdrawn(address indexed to, uint256 amount);
}
