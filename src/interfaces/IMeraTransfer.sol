// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.34;

/// @notice Describes a transfer of an abstract right or entitlement managed by a MERA wallet (design draft).
/// @dev Final types and on-chain usage are subject to product decisions; implementers extend this as needed.
interface IMeraTransfer {
    /// @notice Category of right being transferred (e.g. role, allowance scope, governance).
    enum RightKind {
        Unspecified,
        Role,
        Allowance,
        Governance
    }

    struct TransferIntent {
        /// @dev Recipient of the right after migration or handover.
        address recipient;
        /// @dev Kind of right (extend enum as products require).
        RightKind kind;
        /// @dev Optional amount or weight (e.g. shares, token amount cap).
        uint256 amount;
        /// @dev Optional deadline or valid-unix timestamp for the intent.
        uint64 validUntil;
        /// @dev Opaque payload (e.g. contract-specific metadata hash).
        bytes data;
    }
}
