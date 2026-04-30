// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.34;

import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import {SignatureChecker} from "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";
import {IMERALoginAuthorizationVerifier} from "./interfaces/IMERALoginAuthorizationVerifier.sol";

/// @title MERALoginSignatureVerifier
/// @notice Verifies MERA login deployment authorizations signed by an EOA or EIP-1271 wallet.
contract MERALoginSignatureVerifier is EIP712, IMERALoginAuthorizationVerifier {
    bytes32 public constant AUTHORIZATION_TYPEHASH = keccak256(
        "LoginAuthorization(address registry,address factory,bytes32 loginHash,address wallet,uint256 chainId,uint256 deadline)"
    );

    address public immutable AUTHORIZER;

    error InvalidAuthorizer();
    error AuthorizationExpired();
    error InvalidAuthorization();

    constructor(address authorizer) EIP712("MERA Login Authorization", "1") {
        require(authorizer != address(0), InvalidAuthorizer());
        AUTHORIZER = authorizer;
    }

    function validateRegistration(
        address registry,
        address factory,
        bytes32 loginHash,
        string calldata,
        address wallet,
        uint256 deadline,
        bytes calldata authorization
    ) external view {
        require(authorization.length != 0, InvalidAuthorization());
        require(block.timestamp <= deadline, AuthorizationExpired());
        bytes32 digest = hashAuthorization(registry, factory, loginHash, wallet, deadline);
        require(SignatureChecker.isValidSignatureNow(AUTHORIZER, digest, authorization), InvalidAuthorization());
    }

    function hashAuthorization(address registry, address factory, bytes32 loginHash, address wallet, uint256 deadline)
        public
        view
        returns (bytes32)
    {
        return _hashTypedDataV4(
            keccak256(abi.encode(AUTHORIZATION_TYPEHASH, registry, factory, loginHash, wallet, block.chainid, deadline))
        );
    }
}
