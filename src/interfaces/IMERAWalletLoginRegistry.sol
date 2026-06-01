// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.34;

import {IMERAWalletLoginRegistryMigration} from "./IMERAWalletLoginRegistryMigration.sol";

/// @notice External API of MERAWalletLoginRegistry (numeric bounds live in {MERAWalletLoginRegistryConstants}).
interface IMERAWalletLoginRegistry is IMERAWalletLoginRegistryMigration {
    /// @notice Optional authorization verifier used for short-login registrations.
    function authorizationVerifier() external view returns (address);
    /// @notice Whether short paid logins require verifier authorization.
    function REQUIRE_SHORT_LOGIN_AUTHORIZATION() external view returns (bool);
    /// @notice Returns whether `factory` may register logins.
    function isFactory(address factory) external view returns (bool allowed);
    /// @dev Zero means absent; otherwise value is `committedAt + 1` for the matching commitment.
    function commitments(bytes32 commitment) external view returns (uint256 committedAtPlusOne);
    /// @notice Wallet registered for `loginHash`.
    function walletByLoginHash(bytes32 loginHash) external view returns (address wallet);
    /// @notice Login hash registered for `wallet`.
    function loginHashByWallet(address wallet) external view returns (bytes32 loginHash);
    /// @notice Referrer login hash recorded for a login hash.
    function referrerLoginHashByLoginHash(bytes32 loginHash) external view returns (bytes32 referrerLoginHash);
    /// @dev Matches the compiler-generated getter for the public mapping (struct fields as a tuple).
    function pendingLoginMigrationByOldLoginHash(bytes32 oldLoginHash)
        external
        view
        returns (address previousWallet, address newWallet, bytes32 newLoginHash);
    /// @notice Expiry timestamp for a pending login migration; zero means absent.
    function pendingLoginMigrationExpiresAtByOldLoginHash(bytes32 oldLoginHash)
        external
        view
        returns (uint256 expiresAt);
    /// @notice Base paid-login price.
    function baseLoginPrice() external view returns (uint256);
    /// @notice Multiplier applied to shorter paid logins.
    function loginPriceMultiplier() external view returns (uint256);

    /// @notice Allows a wallet factory to register logins.
    function addFactory(address factory) external;
    /// @notice Sets the optional registration authorization verifier.
    function setAuthorizationVerifier(address newVerifier) external;
    /// @notice Sets the base paid-login price.
    function setBaseLoginPrice(uint256 newBaseLoginPrice) external;
    /// @notice Sets the short-login price multiplier.
    function setLoginPriceMultiplier(uint256 newMultiplier) external;
    /// @notice Withdraws collected ETH to the owner.
    function withdraw() external;
    /// @notice Stores a login registration commitment.
    function commit(bytes32 commitment) external;

    /// @notice Registers `login` for `wallet` after validating commitment, payment, and optional authorization.
    function registerLogin(
        string calldata login,
        address wallet,
        bytes32 secret,
        uint256 deadline,
        bytes calldata authorization,
        string calldata referrerLogin
    ) external payable;

    /// @notice Sets the caller wallet's referrer login once.
    function setReferrer(string calldata referrerLogin) external;

    /// @notice Returns the registration price for `login`.
    function priceOf(string calldata login) external view returns (uint256);
    /// @notice Returns the wallet registered to `login`.
    function walletOf(string calldata login) external view returns (address);
    /// @notice Returns the login string registered to `wallet`.
    function loginOf(address wallet) external view returns (string memory);
    /// @notice Returns the login string registered to `loginHash`.
    function loginByHash(bytes32 loginHash) external view returns (string memory);
    /// @notice Returns the referrer login hash for `login`.
    function referrerLoginHashOf(string calldata login) external view returns (bytes32);
    /// @notice Returns the referrer login string for `login`.
    function referrerLoginOf(string calldata login) external view returns (string memory);
    /// @notice Validates login format and returns its hash.
    function validateLogin(string calldata login) external pure returns (bytes32);

    /// @notice Computes the commitment required for a future registration.
    function makeCommitment(
        string calldata login,
        address wallet,
        address factory,
        bytes32 secret,
        uint256 deadline,
        bytes32 authorizationHash,
        string calldata referrerLogin
    ) external pure returns (bytes32);
}
