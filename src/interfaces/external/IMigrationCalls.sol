// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.34;

interface IMigrationCalls {
    function transferOwnership(address newOwner) external;
    function grantRole(bytes32 role, address account) external;
}
