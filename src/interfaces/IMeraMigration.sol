// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.34;

/// @notice Marker interface for migration-time executors (vault ownership, mass approvals, role grants).
/// @dev Concrete execution paths and authorization are defined in governance/docs — this is a naming/ABI anchor only.
interface IMeraMigration {
    /// @notice Emitted when a migration step is recorded for off-chain tracking.
    /// @dev Optional for implementations of this marker interface.
    event MigrationStep(bytes32 indexed migrationId, bytes32 indexed stepKind, address indexed target);
}
