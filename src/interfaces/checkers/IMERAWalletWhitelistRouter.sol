// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.34;

/// @notice Registry that resolves route hashes to active whitelist contracts.
interface IMERAWalletWhitelistRouter {
    function whitelistByHash(bytes32 routeHash) external view returns (address whitelist);
}
