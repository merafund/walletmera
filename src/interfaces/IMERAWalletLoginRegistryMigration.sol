// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.34;

interface IMERAWalletLoginRegistryMigration {
    function requestLoginMigration(string calldata oldLogin, string calldata newLogin, address newWallet) external;
    function confirmLoginMigration(string calldata oldLogin) external;
}
