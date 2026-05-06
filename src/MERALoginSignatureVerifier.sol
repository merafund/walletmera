// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.34;

import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import {SignatureChecker} from "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";
import {IMERALoginAuthorizationVerifier} from "./interfaces/IMERALoginAuthorizationVerifier.sol";
import {MERAWalletLoginRegistryTypes} from "./types/MERAWalletLoginRegistryTypes.sol";

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

    function validateRegistration(MERAWalletLoginRegistryTypes.RegistrationValidationParams calldata params)
        external
        view
    {
        require(params.authorization.length != 0, InvalidAuthorization());
        require(block.timestamp <= params.deadline, AuthorizationExpired());
        bytes32 digest =
            hashAuthorization(params.registry, params.factory, params.loginHash, params.wallet, params.deadline);
        require(SignatureChecker.isValidSignatureNow(AUTHORIZER, digest, params.authorization), InvalidAuthorization());
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
