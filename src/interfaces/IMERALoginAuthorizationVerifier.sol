// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.34;

import {MERAWalletLoginRegistryTypes} from "../types/MERAWalletLoginRegistryTypes.sol";

interface IMERALoginAuthorizationVerifier {
    function validateRegistration(MERAWalletLoginRegistryTypes.RegistrationValidationParams calldata params)
        external
        view;
}
