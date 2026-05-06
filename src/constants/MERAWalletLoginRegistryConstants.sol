// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.34;

/// @notice Shared constants for MERAWalletLoginRegistry (commitment windows, login format, paid-tier pricing bounds).
library MERAWalletLoginRegistryConstants {
    uint256 internal constant MIN_COMMITMENT_AGE = 60 seconds;
    uint256 internal constant MAX_COMMITMENT_AGE = 15 minutes;
    uint256 internal constant MIN_LOGIN_LENGTH = 3;
    uint256 internal constant MAX_LOGIN_LENGTH = 32;
    uint256 internal constant PAID_LOGIN_MAX_LENGTH = 9;
    uint256 internal constant MIN_BASE_LOGIN_PRICE = 0.00001 ether;
    uint256 internal constant MAX_BASE_LOGIN_PRICE = 1 ether;
    uint256 internal constant MIN_LOGIN_PRICE_MULTIPLIER = 2;
    uint256 internal constant MAX_LOGIN_PRICE_MULTIPLIER = 10;

    /// @dev Initial value for {MERAWalletLoginRegistry.baseLoginPrice} at deployment.
    uint256 internal constant DEFAULT_BASE_LOGIN_PRICE = 0.0005 ether;
    /// @dev Initial value for {MERAWalletLoginRegistry.loginPriceMultiplier} at deployment.
    uint256 internal constant DEFAULT_LOGIN_PRICE_MULTIPLIER = 10;
}
