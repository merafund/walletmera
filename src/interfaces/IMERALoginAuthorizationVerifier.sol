// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.34;

interface IMERALoginAuthorizationVerifier {
    function validateRegistration(
        address registry,
        address factory,
        bytes32 loginHash,
        string calldata login,
        address wallet,
        uint256 deadline,
        bytes calldata authorization
    ) external view;
}
