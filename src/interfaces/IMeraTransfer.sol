// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.34;

/// @notice Describes a transfer of an abstract right or entitlement managed by a MERA wallet (design draft).
/// @dev Final types and on-chain usage are subject to product decisions; implementers extend this as needed.
interface IMeraTransfer {
    /// @notice Category of right being transferred (e.g. role, allowance scope, governance).
    enum RightKind {
        /// @notice No specific right kind was selected.
        Unspecified,
        /// @notice A wallet role or controller authority.
        Role,
        /// @notice An allowance or spending scope.
        Allowance,
        /// @notice A governance power or delegation scope.
        Governance
    }

    /// @notice Draft transfer intent for an abstract MERA-managed right.
    struct TransferIntent {
        /// @notice Recipient of the right after migration or handover.
        address recipient;
        /// @notice Kind of right (extend enum as products require).
        RightKind kind;
        /// @notice Optional amount or weight (e.g. shares, token amount cap).
        uint256 amount;
        /// @notice Optional deadline or valid-unix timestamp for the intent.
        uint64 validUntil;
        /// @notice Opaque payload (e.g. contract-specific metadata hash).
        bytes data;
    }
}
