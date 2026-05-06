// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.34;

import {IMERAWalletLoginRegistryMigration} from "./IMERAWalletLoginRegistryMigration.sol";

/// @notice External API of MERAWalletLoginRegistry (numeric bounds live in {MERAWalletLoginRegistryConstants}).
interface IMERAWalletLoginRegistry is IMERAWalletLoginRegistryMigration {
    function authorizationVerifier() external view returns (address);
    function REQUIRE_SHORT_LOGIN_AUTHORIZATION() external view returns (bool);
    function isFactory(address factory) external view returns (bool allowed);
    /// @dev Zero means absent; otherwise value is `committedAt + 1` for the matching commitment.
    function commitments(bytes32 commitment) external view returns (uint256 committedAtPlusOne);
    function walletByLoginHash(bytes32 loginHash) external view returns (address wallet);
    function loginHashByWallet(address wallet) external view returns (bytes32 loginHash);
    function referrerLoginHashByLoginHash(bytes32 loginHash) external view returns (bytes32 referrerLoginHash);
    /// @dev Matches the compiler-generated getter for the public mapping (struct fields as a tuple).
    function pendingLoginMigrationByOldLoginHash(bytes32 oldLoginHash)
        external
        view
        returns (address previousWallet, address newWallet, bytes32 newLoginHash);
    function baseLoginPrice() external view returns (uint256);
    function loginPriceMultiplier() external view returns (uint256);

    function addFactory(address factory) external;
    function setAuthorizationVerifier(address newVerifier) external;
    function setBaseLoginPrice(uint256 newBaseLoginPrice) external;
    function setLoginPriceMultiplier(uint256 newMultiplier) external;
    function withdraw() external;
    function commit(bytes32 commitment) external;

    function registerLogin(
        string calldata login,
        address wallet,
        bytes32 secret,
        uint256 deadline,
        bytes calldata authorization
    ) external payable;

    function registerLogin(
        string calldata login,
        address wallet,
        bytes32 secret,
        uint256 deadline,
        bytes calldata authorization,
        string calldata referrerLogin
    ) external payable;

    function priceOf(string calldata login) external view returns (uint256);
    function walletOf(string calldata login) external view returns (address);
    function loginOf(address wallet) external view returns (string memory);
    function loginByHash(bytes32 loginHash) external view returns (string memory);
    function referrerLoginHashOf(string calldata login) external view returns (bytes32);
    function referrerLoginOf(string calldata login) external view returns (string memory);
    function validateLogin(string calldata login) external pure returns (bytes32);

    function makeCommitment(
        string calldata login,
        address wallet,
        address factory,
        bytes32 secret,
        uint256 deadline,
        bytes32 authorizationHash
    ) external pure returns (bytes32);

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
