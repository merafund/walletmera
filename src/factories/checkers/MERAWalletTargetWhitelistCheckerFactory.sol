// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.34;

import {MERAWalletTargetWhitelistChecker} from "../../checkers/MERAWalletTargetWhitelistChecker.sol";

/// @notice Deploys {MERAWalletTargetWhitelistChecker} instances.
contract MERAWalletTargetWhitelistCheckerFactory {
    /// @notice Emitted after a checker instance is deployed.
    event Deployed(address indexed instance);

    /// @notice Deploys a new {MERAWalletTargetWhitelistChecker}.
    /// @param initialOwner Owner assigned to the deployed checker.
    /// @return instance Deployed checker instance.
    function deploy(address initialOwner) external returns (MERAWalletTargetWhitelistChecker instance) {
        instance = new MERAWalletTargetWhitelistChecker(initialOwner);
        emit Deployed(address(instance));
    }
}
