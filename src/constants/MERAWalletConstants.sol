// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.34;

/// @notice Shared constants for MERA wallet contracts (EIP-1271, calldata, role ranks, timelock bounds, batch limits).
library MERAWalletConstants {
    // --- EIP-1271 (https://eips.ethereum.org/EIPS/eip-1271) ---
    bytes4 internal constant EIP1271_MAGICVALUE = 0x1626ba7e;
    bytes4 internal constant EIP1271_INVALID = 0xffffffff;

    // --- Calldata ---
    /// @dev Bytes needed to read a function selector from ABI-encoded call `data`.
    uint256 internal constant FUNCTION_SELECTOR_LENGTH = 4;

    // --- Role ranks ({_roleRank} ordering: Primary < Backup < Emergency) ---
    uint256 internal constant ROLE_RANK_NONE = 0;
    uint256 internal constant ROLE_RANK_PRIMARY = 1;
    uint256 internal constant ROLE_RANK_BACKUP = 2;
    uint256 internal constant ROLE_RANK_EMERGENCY = 3;

    // --- Timelock bounds (aligned with uint120 per-path delays in call policies) ---
    uint256 internal constant MIN_TIMELOCK_DELAY = 0;
    uint256 internal constant MAX_TIMELOCK_DELAY = type(uint120).max;

    // --- Batch execution ---
    /// @dev Upper bound on `calls.length` for propose/execute paths to limit gas griefing.
    uint256 internal constant MAX_CALLS_PER_BATCH = 256;

    // --- Required transaction checkers (before/after lists) ---
    /// @dev Upper bound per list to limit gas and griefing on every execution hook.
    uint256 internal constant MAX_REQUIRED_CHECKERS_PER_LIST = 64;

    // --- Self-call selectors: emergency timelock exemptions (config / freeze / life / roles on this wallet) ---
    /// @dev See `cast sig` / ABI; used when `callerRole == Emergency` and `target == address(this)`.
    bytes4 internal constant SEL_SET_PRIMARY = 0xdcd04793;
    bytes4 internal constant SEL_SET_BACKUP = 0xb7dacbf1;
    bytes4 internal constant SEL_SET_EMERGENCY = 0xeb02a115;
    bytes4 internal constant SEL_SET_GLOBAL_TIMELOCK = 0x2d605a02;
    bytes4 internal constant SEL_SET_LIFE_CONTROL = 0xbc05d937;
    bytes4 internal constant SEL_SET_LIFE_CONTROLLERS = 0x2ffa4848;
    bytes4 internal constant SEL_SET_TARGET_CALL_POLICY = 0x49e3232b;
    bytes4 internal constant SEL_SET_SELECTOR_CALL_POLICY = 0x803f9a87;
    bytes4 internal constant SEL_SET_REQUIRED_CHECKER = 0x04afc20a;
    bytes4 internal constant SEL_SET_WHITELISTED_CHECKER = 0x5e775337;
    bytes4 internal constant SEL_SET_CONTROLLER_AGENT = 0x47b80c1c;
    bytes4 internal constant SEL_SET_FROZEN_PRIMARY = 0x1c7f46fe;
    bytes4 internal constant SEL_SET_FROZEN_BACKUP = 0x3a130cf2;
    bytes4 internal constant SEL_SET1271_SIGNER = 0xde31d93a;
    bytes4 internal constant SEL_FREEZE_PRIMARY_BY_AGENT = 0x04138a53;
}
