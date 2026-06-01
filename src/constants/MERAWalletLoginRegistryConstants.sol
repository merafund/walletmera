// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.34;

/// @notice Shared constants for MERAWalletLoginRegistry (commitment windows, login format, paid-tier pricing bounds).
library MERAWalletLoginRegistryConstants {
    /// @notice Minimum age before a login commitment may be consumed.
    uint256 internal constant MIN_COMMITMENT_AGE = 60 seconds;
    /// @notice Maximum age after which a login commitment expires.
    uint256 internal constant MAX_COMMITMENT_AGE = 1 hours;
    /// @notice Maximum age before a pending login migration can be replaced.
    uint256 internal constant LOGIN_MIGRATION_TTL = 1 days;
    /// @notice Minimum login length.
    uint256 internal constant MIN_LOGIN_LENGTH = 3;
    /// @notice Maximum login length.
    uint256 internal constant MAX_LOGIN_LENGTH = 32;
    /// @notice Maximum login length that is still charged using paid short-login pricing.
    uint256 internal constant PAID_LOGIN_MAX_LENGTH = 9;
    /// @notice Minimum allowed base login price.
    uint256 internal constant MIN_BASE_LOGIN_PRICE = 0.00001 ether;
    /// @notice Maximum allowed base login price.
    uint256 internal constant MAX_BASE_LOGIN_PRICE = 1 ether;
    /// @notice Minimum allowed short-login price multiplier.
    uint256 internal constant MIN_LOGIN_PRICE_MULTIPLIER = 2;
    /// @notice Maximum allowed short-login price multiplier.
    uint256 internal constant MAX_LOGIN_PRICE_MULTIPLIER = 10;

    /// @dev Initial value for {MERAWalletLoginRegistry.baseLoginPrice} at deployment.
    uint256 internal constant DEFAULT_BASE_LOGIN_PRICE = 0.0005 ether;
    /// @dev Initial value for {MERAWalletLoginRegistry.loginPriceMultiplier} at deployment.
    uint256 internal constant DEFAULT_LOGIN_PRICE_MULTIPLIER = 10;
}
