// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.34;

/// @notice Registry that resolves route hashes to active whitelist contracts.
interface IMERAWalletWhitelistRouter {
    /// @notice Returns the whitelist registered for `routeHash`.
    /// @param routeHash Route key derived by checker-specific logic.
    /// @return whitelist Whitelist contract address, or zero when unset.
    function whitelistByHash(bytes32 routeHash) external view returns (address whitelist);
}
