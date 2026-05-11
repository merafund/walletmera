// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.34;

/// @notice Minimal target API allowed during wallet migration mode.
interface IMigrationCalls {
    /// @notice Transfers ownership to `newOwner`.
    /// @param newOwner New owner address.
    function transferOwnership(address newOwner) external;
    /// @notice Grants `role` to `account`.
    /// @param role Role identifier.
    /// @param account Account receiving the role.
    function grantRole(bytes32 role, address account) external;
}
