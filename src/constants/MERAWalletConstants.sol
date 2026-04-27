// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.34;

/// @notice Shared constants for MERA wallet contracts (EIP-1271, calldata, role ranks, timelock bounds, batch limits).
library MERAWalletConstants {
    /// @dev Global deterministic CREATE2 deployer (Nick Johnson / Arachnid); same address on chains where it is deployed.
    address internal constant DETERMINISTIC_CREATE2_DEPLOYER = 0x4e59b44847b379578588920cA78FbF26c0B4956C;
    // --- EIP-1271 (https://eips.ethereum.org/EIPS/eip-1271) ---
    bytes4 internal constant EIP1271_MAGICVALUE = 0x1626ba7e;
    bytes4 internal constant EIP1271_INVALID = 0xffffffff;

    // --- Calldata ---
    /// @dev Bytes needed to read a function selector from ABI-encoded call `data`.
    uint256 internal constant FUNCTION_SELECTOR_LENGTH = 4;

    // --- Role ranks (numeric: Primary < Backup < Emergency; agent caps and cancel/clearVeto use {_roleRank}; lower = stronger for wallet authority) ---
    uint256 internal constant ROLE_RANK_NONE = 0;
    uint256 internal constant ROLE_RANK_PRIMARY = 1;
    uint256 internal constant ROLE_RANK_BACKUP = 2;
    uint256 internal constant ROLE_RANK_EMERGENCY = 3;

    // --- Timelock bounds (aligned with uint56 per-path delays in call policies) ---
    uint256 internal constant MIN_TIMELOCK_DELAY = 0;
    uint256 internal constant MAX_TIMELOCK_DELAY = type(uint56).max;

    // --- Batch execution ---
    /// @dev Upper bound on `calls.length` for propose/execute paths to limit gas griefing.
    uint256 internal constant MAX_CALLS_PER_BATCH = 256;

    // --- Required transaction checkers (before/after lists) ---
    /// @dev Upper bound per list to limit gas and griefing on every execution hook.
    uint256 internal constant MAX_REQUIRED_CHECKERS_PER_LIST = 8;

    // --- Safe mode ---
    uint256 internal constant SAFE_MODE_MIN_DURATION = 30 days;
    uint256 internal constant SAFE_MODE_MAX_DURATION = 90 days;
}
