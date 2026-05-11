// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.34;

import {MERAWalletLoginRegistryTypes} from "../types/MERAWalletLoginRegistryTypes.sol";

/// @notice Optional verifier hook used by the login registry before short-login registration.
interface IMERALoginAuthorizationVerifier {
    /// @notice Validates a login registration request.
    /// @param params Registration context supplied by {MERAWalletLoginRegistry}.
    /// @dev Reverts when the registration is not authorized.
    function validateRegistration(MERAWalletLoginRegistryTypes.RegistrationValidationParams calldata params)
        external
        view;
}
